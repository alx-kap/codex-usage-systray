import AppKit

enum AppCommands {
    static func openLegacySettings() {
        NSApp.activate(ignoringOtherApps: true)

        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }

        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    static func openDashboard() {
        guard let url = URL(string: "https://chatgpt.com/codex/settings/usage") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
