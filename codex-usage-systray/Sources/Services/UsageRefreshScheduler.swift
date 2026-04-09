import Foundation

@MainActor
final class UsageRefreshScheduler {
    let normalInterval: TimeInterval
    let backoffInterval: TimeInterval

    private var refreshTimer: Timer?

    init(
        normalInterval: TimeInterval = 5 * 60,
        backoffInterval: TimeInterval = 15 * 60
    ) {
        self.normalInterval = normalInterval
        self.backoffInterval = backoffInterval
    }

    func schedule(after interval: TimeInterval, action: @escaping () -> Void) {
        stop()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func interval(for error: UsageServiceError) -> TimeInterval? {
        switch error {
        case .missingSession, .invalidSession:
            return nil
        case .blockedByCloudflare:
            return backoffInterval
        case .invalidPayload:
            return normalInterval
        case .httpStatus(let statusCode, _):
            return statusCode == 429 ? backoffInterval : normalInterval
        }
    }
}
