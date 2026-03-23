import AppKit
import UserNotifications
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageService = UsageService.shared
    private let settingsManager = SettingsManager.shared
    private var notificationState = UsageNotificationState()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupNotifications()
        startUsagePolling()

        usageService.$currentUsage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.checkForNotifications()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageService.stopPolling()
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    private func startUsagePolling() {
        usageService.startPolling()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkForNotifications()
        }
    }

    @objc private func settingsDidChange() {
        DispatchQueue.main.async {
            self.checkForNotifications()
        }
    }

    private func checkForNotifications() {
        guard settingsManager.settings.notificationsEnabled else { return }

        let evaluation = evaluateUsageNotification(
            currentUsage: usageService.currentUsage.primaryUsedPercent,
            warningThreshold: Int(settingsManager.settings.warningThreshold),
            criticalThreshold: Int(settingsManager.settings.criticalThreshold),
            previousState: notificationState
        )

        notificationState = evaluation.state

        guard let event = evaluation.event else {
            return
        }

        switch event {
        case .critical(let usage):
            sendNotification(
                title: "Critical: ChatGPT Codex Usage",
                body: "You've used \(usage)% of your primary Codex quota. Consider pausing non-essential tasks.",
                isCritical: true
            )
        case .warning(let usage):
            sendNotification(
                title: "Warning: ChatGPT Codex Usage",
                body: "You've used \(usage)% of your primary Codex quota.",
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

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification error: \(error)")
            }
        }
    }
}
