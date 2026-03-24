import SwiftUI
import AppKit

fileprivate enum MenuBarVisualTokens {
    static let contentWidth: CGFloat = 232
    static let rowCornerRadius: CGFloat = 10
    static let containerPadding: CGFloat = 14
    static let rowPadding = EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6)
    static let sectionSpacing: CGFloat = 10
    static let dividerOpacity: Double = 0.18
    static let hoverOpacity: Double = 0.09
}

struct MenuBarView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settingsManager: SettingsManager
    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if usageService.authState.needsSession {
                connectState
            } else {
                usageSection

                if !usageService.currentUsage.breakdowns.isEmpty {
                    sectionDivider
                        .padding(.vertical, MenuBarVisualTokens.sectionSpacing)
                    secondaryMetricsSection
                }

                sectionDivider
                    .padding(.vertical, MenuBarVisualTokens.sectionSpacing)
                actionSection

                sectionDivider
                    .padding(.vertical, MenuBarVisualTokens.sectionSpacing)
                quitSection
            }
        }
        .padding(MenuBarVisualTokens.containerPadding)
        .frame(width: MenuBarVisualTokens.contentWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(.easeOut(duration: 0.22)) {
                    isPresented = true
                }
            }
        }
        .onDisappear {
            isPresented = false
        }
    }

    private var connectState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(tintColor.opacity(0.14))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: usageService.authState == .invalidSession ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(connectTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(connectSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = usageService.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 3) {
                if usageService.hasInstalledCodexAuth {
                    actionRowButton(
                        title: "Use Installed Codex",
                        systemImage: "sparkles",
                        action: refreshUsage
                    )
                }

                actionRowButton(
                    title: usageService.hasInstalledCodexAuth ? "Manual Fallback" : (usageService.authState == .invalidSession ? "Update Session" : "Paste Session"),
                    systemImage: "key.fill",
                    action: openSettings
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 10))
        .animation(sectionAnimation(delay: 0.0), value: isPresented)
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(quotaRows.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    sectionDivider
                        .padding(.vertical, 5)
                }
                quotaRow(entry.element, isPrimary: entry.offset == 0)
            }

            statusFooter
                .padding(.top, 8)
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0.0), value: isPresented)
    }

    private var secondaryMetricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Additional Limits")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(usageService.currentUsage.breakdowns.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 {
                        sectionDivider
                            .padding(.vertical, 5)
                    }
                    secondaryMetricRow(entry.element)
                }
            }
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0.03), value: isPresented)
    }

    private var actionSection: some View {
        VStack(spacing: 2) {
            actionRowButton(title: "Open Dashboard", systemImage: "chart.bar", action: openDashboard)
            actionRowButton(title: "Refresh", systemImage: "arrow.clockwise", action: refreshUsage)
            actionRowButton(title: "Settings", systemImage: "gearshape", action: openSettings)
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0.06), value: isPresented)
    }

    private var quitSection: some View {
        actionRowButton(title: "Quit", systemImage: "power", action: quitApp)
            .opacity(isPresented ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
            .animation(sectionAnimation(delay: 0.09), value: isPresented)
    }

    private var quotaRows: [QuotaRowModel] {
        var rows: [QuotaRowModel] = [
            QuotaRowModel(
                label: normalizedQuotaLabel(usageService.currentUsage.primaryLabel),
                utilization: usageService.currentUsage.primaryUsage,
                usedPercent: usageService.currentUsage.primaryUsedPercent,
                resetIn: usageService.currentUsage.primaryResetIn,
                icon: quotaIconName(
                    for: usageService.currentUsage.primaryLabel,
                    usedPercent: usageService.currentUsage.primaryUsedPercent
                ),
                rank: quotaDisplayRank(for: usageService.currentUsage.primaryLabel)
            )
        ]

        if let secondaryLabel = usageService.currentUsage.secondaryLabel {
            rows.append(
                QuotaRowModel(
                    label: normalizedQuotaLabel(secondaryLabel),
                    utilization: usageService.currentUsage.secondaryUsage,
                    usedPercent: usageService.currentUsage.secondaryUsedPercent,
                    resetIn: usageService.currentUsage.secondaryResetIn,
                    icon: quotaIconName(
                        for: secondaryLabel,
                        usedPercent: usageService.currentUsage.secondaryUsedPercent
                    ),
                    rank: quotaDisplayRank(for: secondaryLabel)
                )
            )
        }

        return rows.sorted {
            if $0.rank == $1.rank {
                return $0.label < $1.label
            }
            return $0.rank < $1.rank
        }
    }

    private var statusFooter: some View {
        Group {
            if let error = usageService.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if usageService.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing usage…")
                        .foregroundStyle(.secondary)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else if let lastUpdated = usageService.currentUsage.lastUpdated {
                Label(updatedStatusText(for: lastUpdated), systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .font(.system(size: 10, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: usageService.isLoading)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: usageService.error)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: usageService.currentUsage.lastUpdated)
    }

    private func quotaRow(_ row: QuotaRowModel, isPrimary: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(usageColor(for: row.usedPercent).opacity(isPrimary ? 0.14 : 0.1))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: row.icon)
                        .font(.system(size: isPrimary ? 12 : 11, weight: .semibold))
                        .foregroundStyle(usageColor(for: row.usedPercent))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(row.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                if let utilization = row.utilization {
                    Text("\(utilization)%")
                        .font(.system(size: isPrimary ? 14 : 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 4)

            if let resetIn = row.resetIn {
                Text(resetIn)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(MenuBarVisualTokens.rowPadding)
    }

    private func secondaryMetricRow(_ metric: UsageBreakdown) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "cpu")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(metric.utilization)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            if let resetIn = metric.resetIn {
                Text(resetIn)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(MenuBarVisualTokens.rowPadding)
    }

    private func actionRowButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 13)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(MenuBarVisualTokens.rowPadding)
            .contentShape(RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(GlassActionButtonStyle())
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(MenuBarVisualTokens.dividerOpacity))
            .frame(height: 0.8)
    }

    private var tintColor: Color {
        usageService.authState == .invalidSession ? .orange : .blue
    }

    private func usageColor(for utilization: Int?) -> Color {
        guard let utilization else { return .primary }
        let criticalThreshold = Int(settingsManager.settings.criticalThreshold)
        let warningThreshold = Int(settingsManager.settings.warningThreshold)
        if utilization >= criticalThreshold { return .red }
        if utilization >= warningThreshold { return .orange }
        return .primary
    }

    private func usageIconName(for utilization: Int?) -> String {
        guard let utilization else { return "chart.pie" }
        if utilization >= 80 { return "exclamationmark.triangle.fill" }
        if utilization >= 50 { return "chart.pie.fill" }
        return "chart.pie"
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func updatedStatusText(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "Updated just now"
        }
        return "Updated \(relativeTimestamp(for: date))"
    }

    private func normalizedQuotaLabel(_ label: String) -> String {
        if label.lowercased().contains("session") {
            return "5 Hour"
        }
        return label
    }

    private func quotaDisplayRank(for label: String) -> Int {
        let lowercase = label.lowercased()
        if lowercase.contains("session") {
            return 0
        }
        if lowercase.contains("week") {
            return 1
        }
        return 2
    }

    private func quotaIconName(for label: String, usedPercent: Int?) -> String {
        let lowercase = label.lowercased()
        if lowercase.contains("session") {
            return usageIconName(for: usedPercent)
        }
        if lowercase.contains("week") {
            return "calendar"
        }
        return "chart.pie"
    }

    private var connectTitle: String {
        if usageService.hasInstalledCodexAuth {
            return usageService.authState == .invalidSession ? "Reconnect Codex" : "Use Installed Codex"
        }
        return usageService.authState == .invalidSession ? "Session expired" : "Connect ChatGPT"
    }

    private var connectSubtitle: String {
        if usageService.hasInstalledCodexAuth {
            return "A local Codex sign-in was detected on this Mac. The app can use it directly, or you can open settings to add a manual fallback session."
        }
        return "Paste the full Cookie header from an authenticated `chatgpt.com/codex/settings/usage` tab."
    }

    private func openDashboard() {
        if let url = URL(string: "https://chatgpt.com/codex/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshUsage() {
        usageService.fetchUsage()
    }

    private func openSettings() {
        Task { @MainActor in
            let menuGlassProfile = currentMenuGlassProfile()
            hideMenuPresentationWindows()
            SettingsWindowPresenter.shared.show(
                settingsManager: settingsManager,
                usageService: usageService,
                preferredGlassProfile: menuGlassProfile
            )
        }
    }

    @MainActor
    private func hideMenuPresentationWindows() {
        for window in NSApp.windows where window.isVisible && isLikelyMenuPresentationWindow(window) {
            window.orderOut(nil)
        }
    }

    private func isLikelyMenuPresentationWindow(_ window: NSWindow) -> Bool {
        let className = NSStringFromClass(type(of: window))
        if className.contains("MenuBarExtra") || className.contains("Popover") {
            return true
        }

        let size = window.frame.size
        let untitledBorderless = window.title.isEmpty && !window.styleMask.contains(.titled)
        let menuLevel = window.level == .popUpMenu || window.level == .statusBar
        return untitledBorderless && menuLevel && size.width < 360 && size.height < 900
    }

    @MainActor
    private func currentMenuGlassProfile() -> MenuGlassProfile? {
        for window in NSApp.windows where window.isVisible && isLikelyMenuPresentationWindow(window) {
            if let visualEffectView = window.contentView?.firstDescendant(of: NSVisualEffectView.self) {
                return MenuGlassProfile(
                    material: visualEffectView.material,
                    blendingMode: visualEffectView.blendingMode,
                    state: visualEffectView.state
                )
            }
        }
        return nil
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func sectionAnimation(delay: Double) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.14).delay(delay)
        }
        return .spring(response: 0.34, dampingFraction: 0.9).delay(delay)
    }
}

struct StatusItemLabelView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        Group {
            if usageService.authState.needsSession {
                HStack(spacing: 4) {
                    Image(systemName: usageService.authState == .invalidSession ? "exclamationmark.triangle.fill" : "key.fill")
                    Text(usageService.authState == .invalidSession ? "Expired" : "Connect")
                }
                .foregroundStyle(.primary)
            } else if settingsManager.settings.compactDisplay, !usageService.currentUsage.menuBarTextSegments.isEmpty {
                Text(compactStatusText)
                    .foregroundStyle(.primary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: iconName(for: usageService.currentUsage.primaryUsedPercent))
                    Text(labelText)
                        .foregroundStyle(usageColor(for: usageService.currentUsage.primaryUsedPercent))
                }
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .fixedSize()
    }

    private var compactStatusText: String {
        usageService.currentUsage.menuBarTextSegments
            .map { "\($0.usage)%" }
            .joined(separator: " · ")
    }

    private var labelText: String {
        if let primaryUsage = usageService.currentUsage.primaryUsage {
            return "\(primaryUsage)%"
        }
        return usageService.currentUsage.primaryLabel
    }

    private func iconName(for percentage: Int?) -> String {
        guard let percentage else { return "chart.pie" }
        if percentage >= 80 { return "exclamationmark.triangle.fill" }
        if percentage >= 50 { return "chart.pie.fill" }
        return "chart.pie"
    }

    private func usageColor(for percentage: Int?) -> Color {
        guard let percentage else { return .primary }
        let criticalThreshold = Int(settingsManager.settings.criticalThreshold)
        let warningThreshold = Int(settingsManager.settings.warningThreshold)
        if percentage >= criticalThreshold {
            return .red
        }
        if percentage >= warningThreshold {
            return .orange
        }
        return .primary
    }
}

private struct QuotaRowModel {
    let label: String
    let utilization: Int?
    let usedPercent: Int?
    let resetIn: String?
    let icon: String
    let rank: Int
}

private struct MenuGlassProfile {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
}

@MainActor
private final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private var closeObserver: WindowCloseObserver?

    private init() {}

    func show(
        settingsManager: SettingsManager,
        usageService: UsageService,
        preferredGlassProfile: MenuGlassProfile? = nil
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let windowSize = CGSize(width: 460, height: 520)

        let window = BorderlessKeyWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.center()
        window.collectionBehavior = [.transient, .moveToActiveSpace]

        let visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: windowSize))
        let glassProfile = preferredGlassProfile ?? MenuGlassProfile(
            material: .menu,
            blendingMode: .behindWindow,
            state: .followsWindowActiveState
        )
        visualEffectView.material = glassProfile.material
        visualEffectView.blendingMode = glassProfile.blendingMode
        visualEffectView.state = glassProfile.state
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 28
        visualEffectView.layer?.masksToBounds = true

        let rootView = SettingsView(
            settingsManager: settingsManager,
            usageService: usageService,
            onClose: { [weak window] in
                window?.close()
            }
        )
        .background(.clear)
        .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        window.contentView = visualEffectView
        let closeObserver = WindowCloseObserver { [weak self] in
            self?.window = nil
            self?.closeObserver = nil
        }
        self.closeObserver = closeObserver
        window.delegate = closeObserver

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class WindowCloseObserver: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSView {
    func firstDescendant<T: NSView>(of viewType: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: viewType) {
                return match
            }
        }
        return nil
    }
}

private struct GlassActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverActionBody(configuration: configuration)
    }
}

private struct HoverActionBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.18)
        }
        if isHovered {
            return Color.primary.opacity(MenuBarVisualTokens.hoverOpacity)
        }
        return .clear
    }

    private var strokeOpacity: Double {
        if isHovered || configuration.isPressed {
            return 0.04
        }
        return 0.02
    }
}
