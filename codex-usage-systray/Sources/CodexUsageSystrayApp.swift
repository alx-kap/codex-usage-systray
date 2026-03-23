import SwiftUI

@main
struct CodexUsageSystrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var usageService = UsageService.shared
    @StateObject private var settingsManager = SettingsManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                usageService: usageService,
                settingsManager: settingsManager
            )
        } label: {
            StatusItemLabelView(
                usageService: usageService,
                settingsManager: settingsManager
            )
        }
        .menuBarExtraStyle(.window)
    }
}
