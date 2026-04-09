import Foundation
import OSLog
import Security

protocol SessionCredentialStore {
    func readSessionCookie() throws -> String
    func saveSessionCookie(_ cookie: String) throws
    func clearSessionCookie() throws
    func hasSessionCookie() -> Bool
}

protocol InstalledCodexAuthProviding {
    var authFilePath: String { get }
    func readAccessToken() throws -> String
    func hasAccessToken() -> Bool
}

final class InstalledCodexAuthProvider: InstalledCodexAuthProviding {
    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
            }
        }

        let authMode: String?
        let tokens: Tokens

        enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case tokens
        }
    }

    private let logger = Logger(subsystem: "com.chatgpt.codex-usage-tray", category: "InstalledAuth")
    let authFilePath: String

    init(authFilePath: String = NSString(string: "~/.codex/auth.json").expandingTildeInPath) {
        self.authFilePath = authFilePath
    }

    func readAccessToken() throws -> String {
        let url = URL(fileURLWithPath: authFilePath)
        let data = try Data(contentsOf: url)
        let authFile = try JSONDecoder().decode(AuthFile.self, from: data)
        let token = authFile.tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            logger.error("Installed Codex auth file exists but access token was empty")
            throw InstalledCodexAuthError.missingToken
        }

        return token
    }

    func hasAccessToken() -> Bool {
        (try? readAccessToken()) != nil
    }
}

final class KeychainSessionCredentialStore: SessionCredentialStore {
    private enum Constants {
        static let service = "ChatGPTCodexUsageTray"
        static let account = "chatgpt-session-cookie"
    }

    func readSessionCookie() throws -> String {
        var result: AnyObject?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let cookie = String(data: data, encoding: .utf8),
              !cookie.isEmpty
        else {
            throw SessionCredentialError.missingSession
        }

        return cookie
    }

    func saveSessionCookie(_ cookie: String) throws {
        let data = Data(cookie.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.account
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        let addQuery = baseQuery.merging(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SessionCredentialError.keychainFailure(addStatus)
        }
    }

    func clearSessionCookie() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionCredentialError.keychainFailure(status)
        }
    }

    func hasSessionCookie() -> Bool {
        (try? readSessionCookie()) != nil
    }
}

enum SessionCredentialError: LocalizedError {
    case missingSession
    case invalidFormat
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Session cookie not found. Paste the full Cookie header from an authenticated chatgpt.com Codex usage page."
        case .invalidFormat:
            return "Paste the full Cookie header or raw cookie string from chatgpt.com. The value should contain key=value pairs separated by semicolons."
        case .keychainFailure(let status):
            return "Keychain error (\(status))."
        }
    }
}

enum InstalledCodexAuthError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Installed Codex auth was detected, but no access token could be read from ~/.codex/auth.json."
        }
    }
}

enum UsageServiceError: LocalizedError, Equatable {
    case missingSession
    case invalidSession
    case blockedByCloudflare
    case invalidPayload
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "No ChatGPT credentials available. Sign in to the Codex desktop app or paste a fallback Cookie header from chatgpt.com/codex/settings/usage."
        case .invalidSession:
            return "The available ChatGPT credentials are no longer valid. Reopen Codex to refresh its auth, or paste a fresh fallback Cookie header from chatgpt.com/codex/settings/usage."
        case .blockedByCloudflare:
            return "ChatGPT returned a Cloudflare challenge for the fallback browser session. Reopen the usage page and paste the full Cookie header again if you need the manual fallback."
        case .invalidPayload:
            return "ChatGPT returned usage data, but the app couldn't recognize any quota metrics yet."
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}

enum UsageRequestCredential: Equatable {
    case installedCodexBearer(String)
    case sessionCookie(String)

    var source: UsageCredentialSource {
        switch self {
        case .installedCodexBearer:
            return .installedCodex
        case .sessionCookie:
            return .storedSessionCookie
        }
    }
}
