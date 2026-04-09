import Foundation

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

private enum JSONValue: Decodable {
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

enum UsageParser {
    static func parseUsageResponse(data: Data, mimeType: String? = nil) throws -> CodexUsageResponse {
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

    static func makeUsageSnapshot(from response: CodexUsageResponse, now: Date = Date()) -> UsageSnapshot {
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

    private static func decodeHTMLEntities(_ text: String) -> String {
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

    private static func sanitizeMetricLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preferredMetricRank(_ label: String) -> Int {
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

    private static func dedupeAndSortMetrics(_ metrics: [CodexUsageMetric]) -> [CodexUsageMetric] {
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

    private static func percentFromString(_ text: String) -> Int? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = try? NSRegularExpression(pattern: #"(\d{1,3})\s*%"#).firstMatch(in: text, range: range),
              let percentRange = Range(match.range(at: 1), in: text),
              let percent = Int(text[percentRange])
        else {
            return nil
        }
        return min(percent, 100)
    }

    private static func isResetLine(_ text: String) -> Bool {
        text.lowercased().contains("reset")
    }

    private static func isLikelyMetricLabel(_ text: String) -> Bool {
        text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil && !isResetLine(text)
    }

    private static func windowLabel(limitWindowSeconds: Int?, path: [String], baseLabel: String? = nil) -> String {
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

    private static func metricFromWHAMWindow(
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

        let utilization = min(Int(usedPercent.rounded(.down)), 100)

        return CodexUsageMetric(
            label: windowLabel(limitWindowSeconds: limitWindowSeconds, path: path, baseLabel: baseLabel),
            utilization: utilization,
            displayPercent: max(0, 100 - utilization),
            resetAt: resetAt,
            resetDescription: nil
        )
    }

    private static func parseMetricsFromWHAMJSONValue(_ value: JSONValue) -> [CodexUsageMetric] {
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
           let metric = metricFromWHAMWindow(
               object: primaryWindow,
               path: ["code_review_rate_limit", "primary_window"],
               baseLabel: "Code review"
           ) {
            metrics.append(metric)
        }

        return dedupeAndSortMetrics(metrics)
    }

    private static func metricFromJSONObject(_ object: [String: JSONValue], path: [String]) -> CodexUsageMetric? {
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

    private static func collectMetrics(from value: JSONValue, path: [String] = [], into metrics: inout [CodexUsageMetric]) {
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

    private static func parseMetricsFromJSONData(_ data: Data) -> [CodexUsageMetric] {
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

    private static func parseMetricsFromEmbeddedJSON(in html: String) -> [CodexUsageMetric] {
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

    private static func parseMetricsFromHTML(_ html: String) -> [CodexUsageMetric] {
        let stripped = html
            .replacingOccurrences(
                of: #"(?i)</(div|section|article|p|li|h[1-6]|span|tr|td|th)>"#,
                with: "\n",
                options: .regularExpression
            )
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

            if isLikelyMetricLabel(line),
               let nextLine = lines[safe: index + 1],
               let utilization = percentFromString(nextLine) {
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

    let cookie = flattened
        .replacingOccurrences(of: #"^Cookie:\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #";\s*;"#, with: ";", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard cookie.contains("=") else {
        throw SessionCredentialError.invalidFormat
    }

    return cookie
}

func parseUsageResponse(data: Data, mimeType: String? = nil) throws -> CodexUsageResponse {
    try UsageParser.parseUsageResponse(data: data, mimeType: mimeType)
}

func makeUsageSnapshot(from response: CodexUsageResponse, now: Date = Date()) -> UsageSnapshot {
    UsageParser.makeUsageSnapshot(from: response, now: now)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
