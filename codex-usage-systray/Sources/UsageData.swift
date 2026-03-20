import Foundation

struct AppSettings: Codable {
    var warningThreshold: Double = 80.0
    var criticalThreshold: Double = 90.0
    var notificationsEnabled: Bool = true
    var compactDisplay: Bool = true
}

enum UsageAuthState: Equatable {
    case missingSession
    case validating
    case configured
    case invalidSession

    var needsSession: Bool {
        switch self {
        case .missingSession, .invalidSession:
            return true
        case .configured, .validating:
            return false
        }
    }
}

enum UsageCredentialSource: Equatable {
    case installedCodex
    case storedSessionCookie

    var badgeText: String {
        switch self {
        case .installedCodex:
            return "Installed Codex"
        case .storedSessionCookie:
            return "Stored Fallback"
        }
    }
}

struct UsageBreakdown: Equatable {
    let label: String
    let utilization: Int
    let usedPercent: Int
    let resetIn: String?
}

struct UsageSnapshot {
    let primaryUsage: Int?
    let primaryUsedPercent: Int?
    let primaryLabel: String
    let primaryResetIn: String?
    let secondaryUsage: Int?
    let secondaryUsedPercent: Int?
    let secondaryLabel: String?
    let secondaryResetIn: String?
    let breakdowns: [UsageBreakdown]
    let lastUpdated: Date?
    let errorState: String?

    var menuBarTextSegments: [(label: String, usage: Int, usedPercent: Int)] {
        var segments: [(label: String, usage: Int, usedPercent: Int)] = []
        if let primaryUsage, let primaryUsedPercent {
            segments.append((primaryLabel, primaryUsage, primaryUsedPercent))
        }
        if let secondaryUsage, let secondaryLabel, let secondaryUsedPercent {
            segments.append((secondaryLabel, secondaryUsage, secondaryUsedPercent))
        }
        return segments
    }

    var primaryDisplayText: String {
        guard let primaryUsage else { return primaryLabel }
        return "\(primaryLabel): \(primaryUsage)%"
    }

    static var empty: UsageSnapshot {
        UsageSnapshot(
            primaryUsage: nil,
            primaryUsedPercent: nil,
            primaryLabel: "Connect ChatGPT",
            primaryResetIn: nil,
            secondaryUsage: nil,
            secondaryUsedPercent: nil,
            secondaryLabel: nil,
            secondaryResetIn: nil,
            breakdowns: [],
            lastUpdated: nil,
            errorState: nil
        )
    }
}

struct UsageNotificationState: Equatable {
    var lastWarningNotified: Int = 0
    var lastCriticalNotified: Int = 0
}

enum UsageNotificationEvent: Equatable {
    case warning(Int)
    case critical(Int)
}

func evaluateUsageNotification(
    currentUsage: Int?,
    warningThreshold: Int,
    criticalThreshold: Int,
    previousState: UsageNotificationState
) -> (event: UsageNotificationEvent?, state: UsageNotificationState) {
    guard let currentUsage else {
        return (nil, UsageNotificationState())
    }

    var state = previousState

    if currentUsage < warningThreshold {
        state.lastWarningNotified = 0
    }
    if currentUsage < criticalThreshold {
        state.lastCriticalNotified = 0
    }

    if currentUsage >= criticalThreshold && state.lastCriticalNotified < criticalThreshold {
        state.lastCriticalNotified = criticalThreshold
        return (.critical(currentUsage), state)
    }

    if currentUsage >= warningThreshold && currentUsage < criticalThreshold && state.lastWarningNotified < warningThreshold {
        state.lastWarningNotified = warningThreshold
        return (.warning(currentUsage), state)
    }

    return (nil, state)
}
