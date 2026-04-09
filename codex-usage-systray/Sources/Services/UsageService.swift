import Foundation
import OSLog

@MainActor
final class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published private(set) var currentUsage: UsageSnapshot = .empty
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var authState: UsageAuthState
    @Published private(set) var activeCredentialSource: UsageCredentialSource?

    private let credentialStore: SessionCredentialStore
    private let installedCodexAuthProvider: InstalledCodexAuthProviding
    private let client: UsageClient
    private let refreshScheduler: UsageRefreshScheduler
    private let logger = Logger(subsystem: "com.chatgpt.codex-usage-tray", category: "UsageService")

    init(
        credentialStore: SessionCredentialStore = KeychainSessionCredentialStore(),
        installedCodexAuthProvider: InstalledCodexAuthProviding = InstalledCodexAuthProvider(),
        urlSession: URLSession = .shared,
        refreshScheduler: UsageRefreshScheduler? = nil
    ) {
        self.credentialStore = credentialStore
        self.installedCodexAuthProvider = installedCodexAuthProvider
        self.client = UsageClient(urlSession: urlSession)
        self.refreshScheduler = refreshScheduler ?? UsageRefreshScheduler()

        if installedCodexAuthProvider.hasAccessToken() {
            authState = .configured
            activeCredentialSource = .installedCodex
        } else if credentialStore.hasSessionCookie() {
            authState = .configured
            activeCredentialSource = .storedSessionCookie
        } else {
            authState = .missingSession
            activeCredentialSource = nil
        }
    }

    var urlSession: URLSession {
        get { client.urlSession }
        set { client.urlSession = newValue }
    }

    var hasStoredSession: Bool {
        credentialStore.hasSessionCookie()
    }

    var hasInstalledCodexAuth: Bool {
        installedCodexAuthProvider.hasAccessToken()
    }

    var installedCodexAuthPath: String {
        installedCodexAuthProvider.authFilePath
    }

    var hasAvailableCredential: Bool {
        hasInstalledCodexAuth || hasStoredSession
    }

    func startPolling() {
        guard hasAvailableCredential else {
            transitionToMissingSession()
            return
        }

        fetchUsage()
    }

    func stopPolling() {
        refreshScheduler.stop()
    }

    func fetchUsage() {
        guard hasAvailableCredential else {
            transitionToMissingSession()
            return
        }

        isLoading = true

        Task { [weak self] in
            guard let self else { return }

            let credentials = availableCredentials()
            guard !credentials.isEmpty else {
                self.handleFetchFailure(.missingSession)
                return
            }

            var lastError: UsageServiceError = .missingSession

            for credential in credentials {
                do {
                    let response = try await self.client.fetchCodexUsage(credential: credential)
                    let snapshot = makeUsageSnapshot(from: response)

                    self.currentUsage = snapshot
                    self.error = nil
                    self.authState = .configured
                    self.activeCredentialSource = credential.source
                    self.isLoading = false
                    self.scheduleNextFetch(after: self.refreshScheduler.normalInterval)
                    return
                } catch let serviceError as UsageServiceError {
                    lastError = serviceError
                } catch {
                    lastError = .httpStatus(-1, error.localizedDescription)
                }
            }

            self.handleFetchFailure(lastError)
        }
    }

    func saveSessionCookie(_ rawValue: String) async throws {
        let cookie = try normalizeSessionCookie(rawValue)

        isLoading = true
        error = nil
        authState = .validating

        do {
            let response = try await client.fetchCodexUsage(credential: .sessionCookie(cookie))
            let snapshot = makeUsageSnapshot(from: response)
            try credentialStore.saveSessionCookie(cookie)

            currentUsage = snapshot
            error = nil
            authState = .configured
            activeCredentialSource = .storedSessionCookie
            isLoading = false
            scheduleNextFetch(after: refreshScheduler.normalInterval)
        } catch {
            logger.error("Failed to validate or save fallback session: \(error.localizedDescription)")
            isLoading = false
            authState = hasAvailableCredential ? .configured : .invalidSession
            activeCredentialSource = preferredCredentialSource()
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    func clearSessionCookie() {
        do {
            try credentialStore.clearSessionCookie()
        } catch {
            logger.error("Failed to clear stored fallback session: \(error.localizedDescription)")
        }

        error = nil
        isLoading = false

        guard !hasInstalledCodexAuth else {
            authState = .configured
            activeCredentialSource = .installedCodex
            fetchUsage()
            return
        }

        transitionToMissingSession()
    }

    func fetchCodexUsage(credential: UsageRequestCredential) async throws -> CodexUsageResponse {
        try await client.fetchCodexUsage(credential: credential)
    }

    private func availableCredentials() -> [UsageRequestCredential] {
        var credentials: [UsageRequestCredential] = []

        if let accessToken = try? installedCodexAuthProvider.readAccessToken() {
            credentials.append(.installedCodexBearer(accessToken))
        }

        if let sessionCookie = try? credentialStore.readSessionCookie() {
            credentials.append(.sessionCookie(sessionCookie))
        }

        return credentials
    }

    private func handleFetchFailure(_ error: UsageServiceError) {
        logger.error("Usage refresh failed: \(error.localizedDescription)")
        self.error = error.errorDescription
        isLoading = false
        activeCredentialSource = preferredCredentialSource()

        switch error {
        case .missingSession:
            transitionToMissingSession()
        case .invalidSession:
            stopPolling()
            authState = .invalidSession
            currentUsage = .empty
            if !hasAvailableCredential {
                activeCredentialSource = nil
            }
        case .blockedByCloudflare, .invalidPayload, .httpStatus:
            authState = hasAvailableCredential ? .configured : .missingSession
            if let interval = refreshScheduler.interval(for: error) {
                scheduleNextFetch(after: interval)
            }
        }
    }

    private func scheduleNextFetch(after interval: TimeInterval) {
        refreshScheduler.schedule(after: interval) { [weak self] in
            self?.fetchUsage()
        }
    }

    private func transitionToMissingSession() {
        stopPolling()
        currentUsage = .empty
        error = nil
        authState = .missingSession
        activeCredentialSource = nil
        isLoading = false
    }

    private func preferredCredentialSource() -> UsageCredentialSource? {
        if hasInstalledCodexAuth {
            return .installedCodex
        }
        if hasStoredSession {
            return .storedSessionCookie
        }
        return nil
    }
}
