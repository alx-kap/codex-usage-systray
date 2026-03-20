import SwiftUI
import AppKit

fileprivate enum MenuBarVisualTokens {
    static let containerCornerRadius: CGFloat = 17
    static let sectionCornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 9
    static let containerPadding: CGFloat = 5
    static let sectionPadding: CGFloat = 5
    static let rowPadding = EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
    static let sectionSpacing: CGFloat = 4
    static let borderOpacity: Double = 0.18
    static let shadowOpacity: Double = 0.08
    static let hoverOpacity: Double = 0.55
}

struct MenuBarView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settingsManager: SettingsManager
    @State private var showSettings = false
    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PopoverGlassBackground(reduceTransparency: reduceTransparency)
                .clipShape(RoundedRectangle(cornerRadius: MenuBarVisualTokens.containerCornerRadius, style: .continuous))
                .overlay(containerGlow)
                .overlay(containerOverlay)
                .shadow(color: .black.opacity(MenuBarVisualTokens.shadowOpacity), radius: 18, x: 0, y: 8)

            VStack(spacing: MenuBarVisualTokens.sectionSpacing) {
                Group {
                    if usageService.authState.needsSession {
                        connectState
                    } else {
                        usageSection

                        if !usageService.currentUsage.breakdowns.isEmpty {
                            secondaryMetricsSection
                        }

                        actionSection
                        quitSection
                    }
                }
            }
            .padding(MenuBarVisualTokens.containerPadding)
        }
        .frame(width: 232, height: 302, alignment: .top)
        .sheet(isPresented: $showSettings) {
            SettingsView(settingsManager: settingsManager, usageService: usageService)
        }
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

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var containerOverlay: some View {
        RoundedRectangle(cornerRadius: MenuBarVisualTokens.containerCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color(red: 0.72, green: 0.84, blue: 1.0).opacity(0.12),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.9
            )
    }

    private var containerGlow: some View {
        RoundedRectangle(cornerRadius: MenuBarVisualTokens.containerCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(reduceTransparency ? 0.18 : 0.12),
                        Color(red: 0.78, green: 0.9, blue: 1.0).opacity(reduceTransparency ? 0.16 : 0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var connectState: some View {
        GlassSection(delay: 0.0, isPresented: isPresented, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tintColor.opacity(0.14))
                            .frame(width: 26, height: 26)
                        Image(systemName: usageService.authState == .invalidSession ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(connectTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(connectSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let error = usageService.error {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 5) {
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
                        action: { showSettings = true }
                    )
                }
            }
        }
    }

    private var usageSection: some View {
        GlassSection(delay: 0.0, isPresented: isPresented, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(quotaRows.enumerated()), id: \.offset) { entry in
                        if entry.offset > 0 {
                            glassSeparator
                                .padding(.vertical, 3)
                        }
                        quotaRow(entry.element, isPrimary: entry.offset == 0)
                    }
                }

                statusFooter
                    .padding(.top, 4)
            }
        }
    }

    private var secondaryMetricsSection: some View {
        GlassSection(delay: 0.04, isPresented: isPresented, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Additional Limits")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                VStack(spacing: 0) {
                    ForEach(Array(usageService.currentUsage.breakdowns.enumerated()), id: \.offset) { entry in
                        if entry.offset > 0 {
                            glassSeparator
                                .padding(.vertical, 3)
                        }
                        secondaryMetricRow(entry.element)
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        GlassSection(delay: 0.08, isPresented: isPresented, reduceMotion: reduceMotion) {
            VStack(spacing: 0) {
                actionRowButton(title: "Open Dashboard", systemImage: "chart.bar", action: openDashboard)
                glassSeparator
                    .padding(.vertical, 3)
                actionRowButton(title: "Refresh", systemImage: "arrow.clockwise", action: refreshUsage)
                glassSeparator
                    .padding(.vertical, 3)
                actionRowButton(
                    title: usageService.authState.needsSession ? (usageService.hasInstalledCodexAuth ? "Auth Options" : "Paste Session") : "Settings",
                    systemImage: usageService.authState.needsSession ? "key.fill" : "gearshape",
                    action: { showSettings = true }
                )
            }
        }
    }

    private var quitSection: some View {
        GlassSection(delay: 0.12, isPresented: isPresented, reduceMotion: reduceMotion, isDetached: true) {
            actionRowButton(title: "Quit", systemImage: "power", action: quitApp)
        }
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
                footerPill {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if usageService.isLoading {
                footerPill {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing usage…")
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else if let lastUpdated = usageService.currentUsage.lastUpdated {
                footerPill {
                    Label("Updated \(relativeTimestamp(for: lastUpdated))", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: usageService.isLoading)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: usageService.error)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: usageService.currentUsage.lastUpdated)
    }

    private func quotaRow(_ row: QuotaRowModel, isPrimary: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(usageColor(for: row.usedPercent).opacity(isPrimary ? 0.16 : 0.11))
                    .frame(width: 18, height: 18)
                Image(systemName: row.icon)
                    .font(.system(size: isPrimary ? 12 : 11, weight: .semibold))
                    .foregroundStyle(usageColor(for: row.usedPercent))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(row.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                if let utilization = row.utilization {
                    Text("\(utilization)%")
                        .font(.system(size: isPrimary ? 13 : 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 4)

            if let resetIn = row.resetIn {
                Text(resetIn)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(MenuBarVisualTokens.rowPadding)
    }

    private func secondaryMetricRow(_ metric: UsageBreakdown) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 16, height: 16)
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(metric.utilization)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            if let resetIn = metric.resetIn {
                Text(resetIn)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(MenuBarVisualTokens.rowPadding)
    }

    private func footerPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(reduceTransparency ? 0.62 : 0.16),
                                Color(red: 0.76, green: 0.88, blue: 1.0).opacity(reduceTransparency ? 0.2 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.9)
                    )
            )
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
        .buttonStyle(GlassActionButtonStyle(reduceTransparency: reduceTransparency))
    }

    private var glassSeparator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.16),
                        Color(red: 0.76, green: 0.88, blue: 1.0).opacity(0.08),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.75)
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

    private func quitApp() {
        NSApplication.shared.terminate(nil)
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

private struct GlassSection<Content: View>: View {
    let delay: Double
    let isPresented: Bool
    let reduceMotion: Bool
    var isDetached: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(MenuBarVisualTokens.sectionPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MenuBarVisualTokens.sectionCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(shouldReduceTransparency ? 0.52 : 0.16),
                                Color.white.opacity(shouldReduceTransparency ? 0.34 : 0.08),
                                Color(red: 0.77, green: 0.89, blue: 1.0).opacity(isDetached ? 0.12 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MenuBarVisualTokens.sectionCornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        Color(red: 0.76, green: 0.88, blue: 1.0).opacity(0.1),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    )
                    .shadow(color: .black.opacity(isDetached ? 0.045 : 0.03), radius: isDetached ? 8 : 5, x: 0, y: isDetached ? 5 : 2)
            )
            .opacity(isPresented ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 10))
            .animation(
                reduceMotion ? .easeOut(duration: 0.14).delay(delay) : .spring(response: 0.34, dampingFraction: 0.9).delay(delay),
                value: isPresented
            )
    }

    private var shouldReduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

private struct GlassActionButtonStyle: ButtonStyle {
    let reduceTransparency: Bool

    func makeBody(configuration: Configuration) -> some View {
        HoverActionBody(configuration: configuration, reduceTransparency: reduceTransparency)
    }
}

private struct HoverActionBody: View {
    let configuration: ButtonStyle.Configuration
    let reduceTransparency: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.9)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.white.opacity(reduceTransparency ? 0.34 : 0.18)
        }
        if isHovered {
            return Color.white.opacity(reduceTransparency ? 0.22 : MenuBarVisualTokens.hoverOpacity * 0.16)
        }
        return Color.white.opacity(reduceTransparency ? 0.08 : 0.03)
    }

    private var strokeOpacity: Double {
        if isHovered || configuration.isPressed {
            return 0.14
        }
        return 0.04
    }
}

private struct PopoverGlassBackground: NSViewRepresentable {
    let reduceTransparency: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.state = .active
        if reduceTransparency {
            view.material = .windowBackground
            view.isEmphasized = false
        } else {
            view.material = .popover
            view.isEmphasized = false
        }
    }
}
