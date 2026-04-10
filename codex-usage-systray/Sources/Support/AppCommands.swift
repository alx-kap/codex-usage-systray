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

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("com.chatgpt.codex-usage-tray.settings")
    private weak var settingsWindow: NSWindow?
    private var keyObserver: NSObjectProtocol?

    private init() {}

    var hasKnownWindow: Bool {
        settingsWindow != nil
    }

    func revealExistingWindow() {
        guard let settingsWindow else { return }
        present(settingsWindow)
    }

    func register(window: NSWindow) {
        if settingsWindow !== window {
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
            }

            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.present(window)
            }
        }

        settingsWindow = window
        configure(window)
        present(window)
    }

    private func configure(_ window: NSWindow) {
        window.identifier = settingsWindowIdentifier
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    private func present(_ window: NSWindow) {
        configure(window)

        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
