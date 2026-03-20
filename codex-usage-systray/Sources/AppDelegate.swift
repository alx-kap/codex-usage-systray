import AppKit
import SwiftUI
import UserNotifications
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let usageService = UsageService.shared
    private let settingsManager = SettingsManager.shared
    private var notificationState = UsageNotificationState()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupNotifications()
        startUsagePolling()

        usageService.$currentUsage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
                self?.checkForNotifications()
            }
            .store(in: &cancellables)

        usageService.$authState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopover),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

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

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: "ChatGPT Codex Usage")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                usageService: usageService,
                settingsManager: settingsManager
            )
        )
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

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func closePopover() {
        popover.performClose(nil)
    }

    @objc private func settingsDidChange() {
        DispatchQueue.main.async {
            self.updateStatusItemAppearance()
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        if usageService.authState.needsSession {
            button.image = NSImage(systemSymbolName: usageService.authState == .invalidSession ? "exclamationmark.triangle.fill" : "key.fill", accessibilityDescription: "Connect ChatGPT Codex Usage")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            button.attributedTitle = NSAttributedString(
                string: usageService.authState == .invalidSession ? "Expired" : "Connect",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            return
        }

        let snapshot = usageService.currentUsage
        let segments = snapshot.menuBarTextSegments
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        if settingsManager.settings.compactDisplay, !segments.isEmpty {
            let str = NSMutableAttributedString()
            for (index, segment) in segments.enumerated() {
                if index > 0 {
                    str.append(NSAttributedString(
                        string: " · ",
                        attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                    ))
                }

                str.append(NSAttributedString(
                    string: "\(segment.usage)%",
                    attributes: [.font: font, .foregroundColor: usageColor(for: segment.usedPercent)]
                ))
            }

            button.image = nil
            button.attributedTitle = str
            return
        }

        let primaryUsage = snapshot.primaryUsage
        let primaryUsedPercent = snapshot.primaryUsedPercent
        let symbolName = statusItemIconName(for: primaryUsedPercent)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ChatGPT Codex Usage")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        button.attributedTitle = NSAttributedString(
            string: primaryUsage.map { "\($0)%" } ?? snapshot.primaryLabel,
            attributes: [
                .font: font,
                .foregroundColor: usageColor(for: primaryUsedPercent)
            ]
        )
    }

    private func usageColor(for percentage: Int?) -> NSColor {
        guard let percentage else { return .labelColor }
        let criticalThreshold = Int(settingsManager.settings.criticalThreshold)
        let warningThreshold = Int(settingsManager.settings.warningThreshold)
        if percentage >= criticalThreshold {
            return .systemRed
        }
        if percentage >= warningThreshold {
            return .systemOrange
        }
        return .labelColor
    }

    private func statusItemIconName(for percentage: Int?) -> String {
        guard let percentage else { return "chart.pie" }
        if percentage >= 80 { return "exclamationmark.triangle.fill" }
        if percentage >= 50 { return "chart.pie.fill" }
        return "chart.pie"
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
