import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageService = UsageService.shared
    private let settingsManager = SettingsManager.shared
    private let notificationController = UsageNotificationController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        usageService.startPolling()
        notificationController.start(
            usageService: usageService,
            settingsManager: settingsManager
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        notificationController.stop()
        usageService.stopPolling()
    }
}
