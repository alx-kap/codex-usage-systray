import Combine
import Foundation
import OSLog
import UserNotifications

@MainActor
final class UsageNotificationController {
    static let shared = UsageNotificationController()

    private let logger = Logger(subsystem: "com.chatgpt.codex-usage-tray", category: "Notifications")
    private let notificationCenter: UNUserNotificationCenter
    private var notificationState = UsageNotificationState()
    private var cancellables = Set<AnyCancellable>()

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func start(usageService: UsageService, settingsManager: SettingsManager) {
        cancellables.removeAll()
        requestAuthorization()

        Publishers.CombineLatest(usageService.$currentUsage, settingsManager.$settings)
            .receive(on: RunLoop.main)
            .sink { [weak self] usage, settings in
                self?.handleUpdate(usage: usage, settings: settings)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    private func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.error("Notification authorization error: \(error.localizedDescription)")
                return
            }

            logger.debug("Notification authorization completed. Granted: \(granted)")
        }
    }

    private func handleUpdate(usage: UsageSnapshot, settings: AppSettings) {
        guard settings.notificationsEnabled else {
            notificationState = UsageNotificationState()
            return
        }

        let evaluation = evaluateUsageNotification(
            currentUsage: usage.primaryUsedPercent,
            warningThreshold: Int(settings.warningThreshold),
            criticalThreshold: Int(settings.criticalThreshold),
            previousState: notificationState
        )

        notificationState = evaluation.state

        guard let event = evaluation.event else {
            return
        }

        switch event {
        case .critical(let percentage):
            sendNotification(
                title: "Critical: ChatGPT Codex Usage",
                body: "You've used \(percentage)% of your primary Codex quota. Consider pausing non-essential tasks.",
                isCritical: true
            )
        case .warning(let percentage):
            sendNotification(
                title: "Warning: ChatGPT Codex Usage",
                body: "You've used \(percentage)% of your primary Codex quota.",
                isCritical: false
            )
        }
    }

    private func sendNotification(title: String, body: String, isCritical: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isCritical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { [logger] error in
            if let error {
                logger.error("Notification send error: \(error.localizedDescription)")
            }
        }
    }
}
