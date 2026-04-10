import SwiftUI

@MainActor
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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Usage") {
                    usageService.fetchUsage()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Open Dashboard") {
                    AppCommands.openDashboard()
                }
            }

            CommandGroup(replacing: .appSettings) {
                if #available(macOS 14.0, *) {
                    if SettingsWindowController.shared.hasKnownWindow {
                        Button("Settings…") {
                            SettingsWindowController.shared.revealExistingWindow()
                        }
                        .keyboardShortcut(",", modifiers: [.command])
                    } else {
                        SettingsLink {
                            Text("Settings…")
                        }
                        .keyboardShortcut(",", modifiers: [.command])
                    }
                } else {
                    Button("Settings…") {
                        AppCommands.openLegacySettings()
                    }
                    .keyboardShortcut(",", modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView(
                settingsManager: settingsManager,
                usageService: usageService
            )
        }
        .defaultSize(width: 472, height: 560)
        .windowResizability(.contentSize)
    }
}
