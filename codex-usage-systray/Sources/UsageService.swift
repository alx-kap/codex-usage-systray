import Foundation
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
        guard status == errSecSuccess, let data = result as? Data, let cookie = String(data: data, encoding: .utf8), !cookie.isEmpty else {
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

struct CodexUsageMetric: Equatable {
    let label: String
    let utilization: Int
    let displayPercent: Int?
    let resetAt: Date?
    let resetDescription: String?

    var displayedUtilization: Int {
        displayPercent ?? utilization
    }
}

struct CodexUsageResponse: Equatable {
    let metrics: [CodexUsageMetric]
}

enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }
}

func calculateUtilization(tokens: Int, limit: Int) -> Int {
    guard limit > 0 else { return 0 }
    return min(100, tokens * 100 / limit)
}

func formatTimeRemaining(until date: Date, from now: Date = Date()) -> String {
    let interval = date.timeIntervalSince(now)
    if interval <= 0 { return "now" }
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}

func parseUsageDate(_ value: String) -> Date? {
    let formatters: [ISO8601DateFormatter] = [
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }(),
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    ]

    for formatter in formatters {
        if let date = formatter.date(from: value) {
            return date
        }
    }

    return nil
}

func normalizeSessionCookie(_ rawValue: String) throws -> String {
    let flattened = rawValue
        .replacingOccurrences(of: "\r", with: "")
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "; ")

    let cookie = flattened.replacingOccurrences(of: #"^Cookie:\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #";\s*;"#, with: ";", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard cookie.contains("=") else {
        throw SessionCredentialError.invalidFormat
    }

    return cookie
}

private func decodeHTMLEntities(_ text: String) -> String {
    var decoded = text
    let replacements = [
        "&nbsp;": " ",
        "&amp;": "&",
        "&quot;": "\"",
        "&#39;": "'",
        "&lt;": "<",
        "&gt;": ">"
    ]
    for (entity, value) in replacements {
        decoded = decoded.replacingOccurrences(of: entity, with: value)
    }
    return decoded
}

private func sanitizeMetricLabel(_ label: String) -> String {
    label
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func preferredMetricRank(_ label: String) -> Int {
    let lowercase = label.lowercased()
    if lowercase.contains("week") || lowercase.contains("weekly") || lowercase.contains("7d") {
        return 0
    }
    if lowercase.contains("session") || lowercase.contains("5h") || lowercase.contains("day") || lowercase.contains("daily") {
        return 1
    }
    if lowercase.contains("codex") || lowercase.contains("quota") {
        return 2
    }
    return 3
}

private func dedupeAndSortMetrics(_ metrics: [CodexUsageMetric]) -> [CodexUsageMetric] {
    var seen = Set<String>()
    let deduped = metrics.filter { metric in
        let key = "\(sanitizeMetricLabel(metric.label).lowercased())-\(metric.utilization)"
        if seen.contains(key) {
            return false
        }
        seen.insert(key)
        return true
    }

    return deduped.sorted {
        let leftRank = preferredMetricRank($0.label)
        let rightRank = preferredMetricRank($1.label)
        if leftRank == rightRank {
            return $0.label < $1.label
        }
        return leftRank < rightRank
    }
}

private func percentFromString(_ text: String) -> Int? {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = try? NSRegularExpression(pattern: #"(\d{1,3})\s*%"#).firstMatch(in: text, range: range),
          let percentRange = Range(match.range(at: 1), in: text),
          let percent = Int(text[percentRange])
    else {
        return nil
    }
    return min(percent, 100)
}

private func extractResetPhrase(from text: String) -> String? {
    let patterns = [
        #"Resets?\s+(?:at|on|in)\s+[A-Za-z0-9: ]{1,40}"#,
        #"Next reset\s+[A-Za-z0-9: ]{1,40}"#
    ]

    for pattern in patterns {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]).firstMatch(in: text, range: range),
           let matchRange = Range(match.range, in: text) {
            return sanitizeMetricLabel(String(text[matchRange]))
        }
    }

    return nil
}

private func isResetLine(_ text: String) -> Bool {
    let lowercase = text.lowercased()
    return lowercase.contains("reset")
}

private func isLikelyMetricLabel(_ text: String) -> Bool {
    text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil && !isResetLine(text)
}

private func windowLabel(limitWindowSeconds: Int?, path: [String], baseLabel: String? = nil) -> String {
    if let baseLabel {
        return baseLabel
    }

    switch limitWindowSeconds {
    case 18_000:
        return "Session"
    case 86_400:
        return "Daily"
    case 604_800:
        return "Weekly"
    default:
        break
    }

    if path.contains("secondary_window") {
        return "Secondary window"
    }
    if path.contains("primary_window") {
        return "Primary window"
    }

    return path.last?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Usage"
}

private func metricFromWHAMWindow(
    object: [String: JSONValue],
    path: [String],
    baseLabel: String? = nil
) -> CodexUsageMetric? {
    guard let usedPercent = object["used_percent"]?.numberValue else {
        return nil
    }

    let limitWindowSeconds = object["limit_window_seconds"]?.numberValue.map(Int.init)
    let resetAfterSeconds = object["reset_after_seconds"]?.numberValue.map(Int.init)
    let resetAtTimestamp = object["reset_at"]?.numberValue

    let resetAt: Date?
    if let resetAtTimestamp {
        resetAt = Date(timeIntervalSince1970: resetAtTimestamp)
    } else if let resetAfterSeconds {
        resetAt = Date().addingTimeInterval(TimeInterval(resetAfterSeconds))
    } else {
        resetAt = nil
    }

    return CodexUsageMetric(
        label: windowLabel(limitWindowSeconds: limitWindowSeconds, path: path, baseLabel: baseLabel),
        utilization: min(Int(usedPercent.rounded(.down)), 100),
        displayPercent: max(0, 100 - min(Int(usedPercent.rounded(.down)), 100)),
        resetAt: resetAt,
        resetDescription: nil
    )
}

private func parseMetricsFromWHAMJSONValue(_ value: JSONValue) -> [CodexUsageMetric] {
    guard case .object(let rootObject) = value else {
        return []
    }

    var metrics: [CodexUsageMetric] = []

    if let rateLimit = rootObject["rate_limit"]?.objectValue {
        if let primaryWindow = rateLimit["primary_window"]?.objectValue,
           let metric = metricFromWHAMWindow(object: primaryWindow, path: ["rate_limit", "primary_window"]) {
            metrics.append(metric)
        }

        if let secondaryWindow = rateLimit["secondary_window"]?.objectValue,
           let metric = metricFromWHAMWindow(object: secondaryWindow, path: ["rate_limit", "secondary_window"]) {
            metrics.append(metric)
        }
    }

    if let codeReviewRateLimit = rootObject["code_review_rate_limit"]?.objectValue,
       let primaryWindow = codeReviewRateLimit["primary_window"]?.objectValue,
       let metric = metricFromWHAMWindow(object: primaryWindow, path: ["code_review_rate_limit", "primary_window"], baseLabel: "Code review") {
        metrics.append(metric)
    }

    return dedupeAndSortMetrics(metrics)
}

private func metricFromJSONObject(_ object: [String: JSONValue], path: [String]) -> CodexUsageMetric? {
    let labelKeys = ["label", "title", "name", "metric", "window"]
    let utilizationKeys = ["utilization", "percentage", "percent", "pct", "usage_percentage", "used_percentage", "used_percent"]
    let usedKeys = ["used", "consumed", "count"]
    let limitKeys = ["limit", "quota", "max"]
    let resetKeys = ["resets_at", "reset_at", "resetAt", "next_reset_at", "nextResetAt", "resetsOn", "resets_on"]

    let label = labelKeys.compactMap { object[$0]?.stringValue }.first
        ?? path.last(where: { !$0.lowercased().contains("data") && !$0.lowercased().contains("attributes") })

    guard let label, label.count >= 2 else {
        return nil
    }

    var utilization: Int?
    for key in utilizationKeys {
        if let number = object[key]?.numberValue {
            utilization = min(Int(number.rounded(.down)), 100)
            break
        }
        if let string = object[key]?.stringValue, let percent = percentFromString(string) {
            utilization = percent
            break
        }
    }

    if utilization == nil {
        let used = usedKeys.compactMap { object[$0]?.numberValue }.first.map(Int.init)
        let limit = limitKeys.compactMap { object[$0]?.numberValue }.first.map(Int.init)
        if let used, let limit {
            utilization = calculateUtilization(tokens: used, limit: limit)
        }
    }

    guard let utilization else {
        return nil
    }

    let resetString = resetKeys.compactMap { object[$0]?.stringValue }.first
    let resetNumber = object["reset_at"]?.numberValue ?? object["next_reset_at"]?.numberValue
    let resetAt = resetString.flatMap(parseUsageDate(_:)) ?? resetNumber.map { Date(timeIntervalSince1970: $0) }
    let resetDescription = resetString.flatMap { resetAt == nil ? sanitizeMetricLabel($0) : nil }

    return CodexUsageMetric(
        label: sanitizeMetricLabel(label),
        utilization: utilization,
        displayPercent: nil,
        resetAt: resetAt,
        resetDescription: resetDescription
    )
}

private func collectMetrics(from value: JSONValue, path: [String] = [], into metrics: inout [CodexUsageMetric]) {
    switch value {
    case .object(let object):
        if let metric = metricFromJSONObject(object, path: path) {
            metrics.append(metric)
        }
        for (key, nestedValue) in object {
            collectMetrics(from: nestedValue, path: path + [key], into: &metrics)
        }
    case .array(let array):
        for value in array {
            collectMetrics(from: value, path: path, into: &metrics)
        }
    case .string, .number, .bool, .null:
        break
    }
}

private func parseMetricsFromJSONData(_ data: Data) -> [CodexUsageMetric] {
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
        return []
    }

    let whamMetrics = parseMetricsFromWHAMJSONValue(value)
    if !whamMetrics.isEmpty {
        return whamMetrics
    }

    var metrics: [CodexUsageMetric] = []
    collectMetrics(from: value, into: &metrics)
    return dedupeAndSortMetrics(metrics)
}

private func parseMetricsFromEmbeddedJSON(in html: String) -> [CodexUsageMetric] {
    let patterns = [
        #"<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>"#,
        #"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*;"#
    ]

    for pattern in patterns {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let matches = regex?.matches(in: html, range: range) else { continue }

        for match in matches {
            guard match.numberOfRanges > 1, let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let snippet = String(html[jsonRange])
            let metrics = parseMetricsFromJSONData(Data(snippet.utf8))
            if !metrics.isEmpty {
                return metrics
            }
        }
    }

    return []
}

private func parseMetricsFromHTML(_ html: String) -> [CodexUsageMetric] {
    let stripped = html
        .replacingOccurrences(of: #"(?i)</(div|section|article|p|li|h[1-6]|span|tr|td|th)>"#, with: "\n", options: .regularExpression)
        .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)

    let lines = decodeHTMLEntities(stripped)
        .components(separatedBy: .newlines)
        .map(sanitizeMetricLabel(_:))
        .filter { !$0.isEmpty }

    var metrics: [CodexUsageMetric] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]
        defer { index += 1 }

        if isResetLine(line) {
            continue
        }

        if isLikelyMetricLabel(line), let nextLine = lines[safe: index + 1], let utilization = percentFromString(nextLine) {
            let resetDescription = lines[safe: index + 2].flatMap { isResetLine($0) ? sanitizeMetricLabel($0) : nil }
            metrics.append(
                CodexUsageMetric(
                    label: line,
                    utilization: utilization,
                    displayPercent: nil,
                    resetAt: nil,
                    resetDescription: resetDescription
                )
            )
            index += 1
            continue
        }

        if let utilization = percentFromString(line) {
            let previousLabel = lines[safe: index - 1].flatMap { isLikelyMetricLabel($0) ? $0 : nil }
            guard let previousLabel else { continue }
            let resetDescription = lines[safe: index + 1].flatMap { isResetLine($0) ? sanitizeMetricLabel($0) : nil }
            metrics.append(
                CodexUsageMetric(
                    label: previousLabel,
                    utilization: utilization,
                    displayPercent: nil,
                    resetAt: nil,
                    resetDescription: resetDescription
                )
            )
        }
    }

    return dedupeAndSortMetrics(metrics)
}

func parseUsageResponse(data: Data, mimeType: String? = nil) throws -> CodexUsageResponse {
    let body = String(decoding: data, as: UTF8.self)

    if mimeType?.contains("json") == true || body.trimmingCharacters(in: .whitespacesAndNewlines).first == "{" {
        let metrics = parseMetricsFromJSONData(data)
        if !metrics.isEmpty {
            return CodexUsageResponse(metrics: metrics)
        }
    }

    let embeddedMetrics = parseMetricsFromEmbeddedJSON(in: body)
    if !embeddedMetrics.isEmpty {
        return CodexUsageResponse(metrics: embeddedMetrics)
    }

    let htmlMetrics = parseMetricsFromHTML(body)
    if !htmlMetrics.isEmpty {
        return CodexUsageResponse(metrics: htmlMetrics)
    }

    throw UsageServiceError.invalidPayload
}

func makeUsageSnapshot(from response: CodexUsageResponse, now: Date = Date()) -> UsageSnapshot {
    let metrics = dedupeAndSortMetrics(response.metrics)
    let primary = metrics.first
    let secondary = metrics.dropFirst().first
    let remainingBreakdowns = Array(metrics.dropFirst(secondary == nil ? 1 : 2))

    func resetText(for metric: CodexUsageMetric?) -> String? {
        guard let metric else { return nil }
        if let resetDescription = metric.resetDescription {
            return resetDescription
        }
        if let resetAt = metric.resetAt {
            return formatTimeRemaining(until: resetAt, from: now)
        }
        return nil
    }

    return UsageSnapshot(
        primaryUsage: primary?.displayedUtilization,
        primaryUsedPercent: primary?.utilization,
        primaryLabel: primary?.label ?? "Usage",
        primaryResetIn: resetText(for: primary),
        secondaryUsage: secondary?.displayedUtilization,
        secondaryUsedPercent: secondary?.utilization,
        secondaryLabel: secondary?.label,
        secondaryResetIn: resetText(for: secondary),
        breakdowns: remainingBreakdowns.map {
            UsageBreakdown(
                label: $0.label,
                utilization: $0.displayedUtilization,
                usedPercent: $0.utilization,
                resetIn: resetText(for: $0)
            )
        },
        lastUpdated: now,
        errorState: nil
    )
}

final class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published private(set) var currentUsage: UsageSnapshot = .empty
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var authState: UsageAuthState
    @Published private(set) var activeCredentialSource: UsageCredentialSource?

    private let credentialStore: SessionCredentialStore
    private let installedCodexAuthProvider: InstalledCodexAuthProviding
    private var refreshTimer: Timer?
    private let normalInterval: TimeInterval = 5 * 60
    private let backoffInterval: TimeInterval = 15 * 60

    var urlSession: URLSession

    init(
        credentialStore: SessionCredentialStore = KeychainSessionCredentialStore(),
        installedCodexAuthProvider: InstalledCodexAuthProviding = InstalledCodexAuthProvider(),
        urlSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.installedCodexAuthProvider = installedCodexAuthProvider
        self.urlSession = urlSession
        if installedCodexAuthProvider.hasAccessToken() {
            self.authState = .configured
            self.activeCredentialSource = .installedCodex
        } else if credentialStore.hasSessionCookie() {
            self.authState = .configured
            self.activeCredentialSource = .storedSessionCookie
        } else {
            self.authState = .missingSession
            self.activeCredentialSource = nil
        }
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
            currentUsage = .empty
            error = nil
            authState = .missingSession
            activeCredentialSource = nil
            return
        }

        fetchUsage()
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func fetchUsage() {
        guard hasAvailableCredential else {
            stopPolling()
            currentUsage = .empty
            authState = .missingSession
            activeCredentialSource = nil
            error = nil
            return
        }

        isLoading = true

        Task {
            let credentials = availableCredentials()

            guard !credentials.isEmpty else {
                await MainActor.run {
                    self.handleFetchFailure(.missingSession)
                }
                return
            }

            var lastError: UsageServiceError = .missingSession

            for credential in credentials {
                do {
                    let response = try await fetchCodexUsage(credential: credential)
                    let snapshot = makeUsageSnapshot(from: response)

                    await MainActor.run {
                        self.currentUsage = snapshot
                        self.error = nil
                        self.authState = .configured
                        self.activeCredentialSource = credential.source
                        self.isLoading = false
                        self.scheduleTimer(interval: self.normalInterval)
                    }
                    return
                } catch let error as UsageServiceError {
                    lastError = error
                } catch {
                    lastError = .httpStatus(-1, error.localizedDescription)
                }
            }

            let terminalError = lastError
            await MainActor.run {
                self.handleFetchFailure(terminalError)
            }
        }
    }

    func saveSessionCookie(_ rawValue: String) async throws {
        let cookie = try normalizeSessionCookie(rawValue)

        await MainActor.run {
            self.isLoading = true
            self.error = nil
            self.authState = .validating
        }

        do {
            let response = try await fetchCodexUsage(credential: .sessionCookie(cookie))
            let snapshot = makeUsageSnapshot(from: response)
            try credentialStore.saveSessionCookie(cookie)

            await MainActor.run {
                self.currentUsage = snapshot
                self.error = nil
                self.authState = .configured
                self.activeCredentialSource = .storedSessionCookie
                self.isLoading = false
                self.scheduleTimer(interval: self.normalInterval)
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.authState = self.hasAvailableCredential ? .configured : .invalidSession
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            throw error
        }
    }

    func clearSessionCookie() {
        try? credentialStore.clearSessionCookie()
        error = nil
        isLoading = false

        guard !hasInstalledCodexAuth else {
            authState = .configured
            activeCredentialSource = .installedCodex
            fetchUsage()
            return
        }

        stopPolling()
        currentUsage = .empty
        authState = .missingSession
        activeCredentialSource = nil
    }

    private func scheduleTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fetchUsage()
        }
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
        self.error = error.errorDescription
        self.isLoading = false
        self.activeCredentialSource = hasInstalledCodexAuth ? .installedCodex : (hasStoredSession ? .storedSessionCookie : nil)

        switch error {
        case .missingSession:
            stopPolling()
            currentUsage = .empty
            authState = .missingSession
            activeCredentialSource = nil
        case .invalidSession:
            stopPolling()
            authState = .invalidSession
            currentUsage = .empty
            if !hasAvailableCredential {
                activeCredentialSource = nil
            }
        case .blockedByCloudflare:
            authState = hasAvailableCredential ? .configured : .missingSession
            scheduleTimer(interval: backoffInterval)
        case .invalidPayload:
            authState = hasAvailableCredential ? .configured : .missingSession
            scheduleTimer(interval: normalInterval)
        case .httpStatus(let statusCode, _):
            authState = hasAvailableCredential ? .configured : .missingSession
            if statusCode == 429 {
                scheduleTimer(interval: backoffInterval)
            } else {
                scheduleTimer(interval: normalInterval)
            }
        }
    }

    func fetchCodexUsage(credential: UsageRequestCredential) async throws -> CodexUsageResponse {
        let request: URLRequest

        switch credential {
        case .installedCodexBearer(let accessToken):
            var whamRequest = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            whamRequest.httpMethod = "GET"
            whamRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            whamRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            whamRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            whamRequest.setValue("CodexUsageSystray/1.0", forHTTPHeaderField: "User-Agent")
            whamRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request = whamRequest
        case .sessionCookie(let sessionCookie):
            var dashboardRequest = URLRequest(url: URL(string: "https://chatgpt.com/codex/settings/usage")!)
            dashboardRequest.httpMethod = "GET"
            dashboardRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            dashboardRequest.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            dashboardRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            dashboardRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            dashboardRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request = dashboardRequest
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageServiceError.httpStatus(-1, "Invalid response")
        }

        let body = String(decoding: data, as: UTF8.self)

        if let mitigation = http.value(forHTTPHeaderField: "cf-mitigated"), mitigation.lowercased() == "challenge" {
            throw UsageServiceError.blockedByCloudflare
        }

        if http.statusCode == 401 {
            throw UsageServiceError.invalidSession
        }

        if http.statusCode == 403 {
            if body.localizedCaseInsensitiveContains("Enable JavaScript and cookies to continue") {
                throw UsageServiceError.blockedByCloudflare
            }
            throw UsageServiceError.invalidSession
        }

        if (300..<400).contains(http.statusCode) {
            throw UsageServiceError.invalidSession
        }

        guard http.statusCode == 200 else {
            throw UsageServiceError.httpStatus(http.statusCode, String(body.prefix(200)))
        }

        return try parseUsageResponse(data: data, mimeType: http.mimeType)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
