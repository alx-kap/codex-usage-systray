import AppKit
import SwiftUI

private enum MenuBarVisualTokens {
    static let contentWidth: CGFloat = 240
    static let containerPadding: CGFloat = 14
    static let rowCornerRadius: CGFloat = 8
    static let rowPadding = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
    static let sectionSpacing: CGFloat = 10
}

struct MenuBarView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settingsManager: SettingsManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if usageService.authState.needsSession {
                connectionSection
            } else {
                quotaSection

                if !usageService.currentUsage.breakdowns.isEmpty {
                    Divider()
                        .padding(.vertical, MenuBarVisualTokens.sectionSpacing)
                    additionalLimitsSection
                }

                Divider()
                    .padding(.vertical, MenuBarVisualTokens.sectionSpacing)
                actionsSection

                Divider()
                    .padding(.vertical, MenuBarVisualTokens.sectionSpacing)
                quitSection
            }
        }
        .padding(MenuBarVisualTokens.containerPadding)
        .frame(width: MenuBarVisualTokens.contentWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            guard !isPresented else { return }
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    isPresented = true
                }
            }
        }
        .onDisappear {
            isPresented = false
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(connectTitle)
                        .font(.headline)
                    Text(connectSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: usageService.authState == .invalidSession ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                    .foregroundStyle(usageService.authState == .invalidSession ? .orange : .accentColor)
            }
            .labelStyle(.titleAndIcon)

            if let error = usageService.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 4) {
                if usageService.hasInstalledCodexAuth {
                    MenuBarActionRow(
                        title: "Use Installed Codex",
                        systemImage: "sparkles",
                        action: refreshUsage
                    )
                }

                MenuBarSettingsLinkRow(
                    title: sessionActionTitle,
                    systemImage: "key.fill"
                )
            }
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0), value: isPresented)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(quotaRows.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    Divider()
                        .padding(.vertical, 5)
                }
                MenuBarQuotaRow(
                    row: entry.element,
                    isPrimary: entry.offset == 0,
                    color: usageColor(for: entry.element.usedPercent)
                )
            }

            statusFooter
                .padding(.top, 8)
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0), value: isPresented)
    }

    private var additionalLimitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Additional Limits")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(usageService.currentUsage.breakdowns.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 {
                        Divider()
                            .padding(.vertical, 5)
                    }
                    MenuBarSecondaryMetricRow(metric: entry.element)
                }
            }
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0.03), value: isPresented)
    }

    private var actionsSection: some View {
        VStack(spacing: 4) {
            MenuBarActionRow(title: "Open Dashboard", systemImage: "chart.bar", action: AppCommands.openDashboard)
            MenuBarActionRow(title: "Refresh", systemImage: "arrow.clockwise", action: refreshUsage)
            MenuBarSettingsLinkRow(title: "Settings", systemImage: "gearshape")
        }
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(sectionAnimation(delay: 0.06), value: isPresented)
    }

    private var quitSection: some View {
        MenuBarActionRow(title: "Quit", systemImage: "power", action: quitApp)
            .opacity(isPresented ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
            .animation(sectionAnimation(delay: 0.09), value: isPresented)
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
            } else if let lastUpdated = usageService.currentUsage.lastUpdated {
                Label(updatedStatusText(for: lastUpdated), systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quotaRows: [MenuBarQuotaRowModel] {
        var rows: [MenuBarQuotaRowModel] = [
            MenuBarQuotaRowModel(
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
                MenuBarQuotaRowModel(
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

    private var connectTitle: String {
        if usageService.hasInstalledCodexAuth {
            return usageService.authState == .invalidSession ? "Reconnect Codex" : "Use Installed Codex"
        }
        return usageService.authState == .invalidSession ? "Session expired" : "Connect ChatGPT"
    }

    private var connectSubtitle: String {
        if usageService.hasInstalledCodexAuth {
            return "A local Codex sign-in was detected on this Mac. You can use it directly, or open settings to add a manual fallback session."
        }
        return "Paste the full Cookie header from an authenticated chatgpt.com Codex usage page."
    }

    private var sessionActionTitle: String {
        if usageService.hasInstalledCodexAuth {
            return "Manual Fallback"
        }
        return usageService.authState == .invalidSession ? "Update Session" : "Paste Session"
    }

    private func refreshUsage() {
        usageService.fetchUsage()
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func usageColor(for utilization: Int?) -> Color {
        guard let utilization else { return .primary }
        let criticalThreshold = Int(settingsManager.settings.criticalThreshold)
        let warningThreshold = Int(settingsManager.settings.warningThreshold)
        if utilization >= criticalThreshold {
            return .red
        }
        if utilization >= warningThreshold {
            return .orange
        }
        return .primary
    }

    private func usageIconName(for utilization: Int?) -> String {
        guard let utilization else { return "chart.pie" }
        if utilization >= 80 { return "exclamationmark.triangle.fill" }
        if utilization >= 50 { return "chart.pie.fill" }
        return "chart.pie"
    }

    private func updatedStatusText(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "Updated just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
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

    private func sectionAnimation(delay: Double) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.14).delay(delay)
        }
        return .spring(response: 0.30, dampingFraction: 0.9).delay(delay)
    }
}

private struct MenuBarQuotaRowModel {
    let label: String
    let utilization: Int?
    let usedPercent: Int?
    let resetIn: String?
    let icon: String
    let rank: Int
}

private struct MenuBarQuotaRow: View {
    let row: MenuBarQuotaRowModel
    let isPrimary: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.icon)
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let utilization = row.utilization {
                    Text("\(utilization)%")
                        .font(isPrimary ? .headline : .body.weight(.semibold))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 4)

            if let resetIn = row.resetIn {
                Text(resetIn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(MenuBarVisualTokens.rowPadding)
    }
}

private struct MenuBarSecondaryMetricRow: View {
    let metric: UsageBreakdown

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(metric.utilization)%")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            if let resetIn = metric.resetIn {
                Text(resetIn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(MenuBarVisualTokens.rowPadding)
    }
}

private struct MenuBarActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MenuBarVisualTokens.rowPadding)
                .contentShape(RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(MenuBarActionButtonStyle())
    }
}

private struct MenuBarSettingsLinkRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        if #available(macOS 14.0, *) {
            if SettingsWindowController.shared.hasKnownWindow {
                Button(action: SettingsWindowController.shared.revealExistingWindow) {
                    rowLabel
                }
                .buttonStyle(MenuBarActionButtonStyle())
            } else {
                SettingsLink {
                    rowLabel
                }
                .buttonStyle(MenuBarActionButtonStyle())
            }
        } else {
            Button(action: AppCommands.openLegacySettings) {
                rowLabel
            }
            .buttonStyle(MenuBarActionButtonStyle())
        }
    }

    private var rowLabel: some View {
        Label(title, systemImage: systemImage)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MenuBarVisualTokens.rowPadding)
            .contentShape(RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous))
    }
}

private struct MenuBarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: MenuBarVisualTokens.rowCornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.10) : .clear)
            )
    }
}
