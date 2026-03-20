import SwiftUI

struct MenuBarView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settingsManager: SettingsManager
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if usageService.authState.needsSession {
                    connectState
                } else {
                    usageState
                }
            }

            Divider()
                .padding(.vertical, 4)

            actionButtons

            Divider()
                .padding(.vertical, 4)

            quitButton
        }
        .padding(.vertical, 8)
        .frame(minWidth: 260)
        .sheet(isPresented: $showSettings) {
            SettingsView(settingsManager: settingsManager, usageService: usageService)
        }
    }

    private var connectState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: usageService.authState == .invalidSession ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                    .foregroundColor(usageService.authState == .invalidSession ? .orange : .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectTitle)
                        .fontWeight(.semibold)
                    Text(connectSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = usageService.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if usageService.hasInstalledCodexAuth {
                Button(action: refreshUsage) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Use Installed Codex")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }

            Button(action: { showSettings = true }) {
                HStack {
                    Image(systemName: "key.fill")
                    Text(usageService.hasInstalledCodexAuth ? "Manual Fallback" : (usageService.authState == .invalidSession ? "Update Session" : "Paste Session"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
    }

    private var usageState: some View {
        VStack(alignment: .leading, spacing: 0) {
            usageHeader

            if !usageService.currentUsage.breakdowns.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                modelBreakdown
            }
        }
    }

    private var usageHeader: some View {
        let rows = quotaRows

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                let row = entry.element
                usageRow(
                    icon: row.icon,
                    color: usageColor(for: row.usedPercent),
                    label: row.label,
                    utilization: row.utilization,
                    resetIn: row.resetIn
                )
            }

            if let error = usageService.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if usageService.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(height: 10)
            } else if let lastUpdated = usageService.currentUsage.lastUpdated {
                Text("Updated \(relativeTimestamp(for: lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    private var quotaRows: [(label: String, utilization: Int?, usedPercent: Int?, resetIn: String?, icon: String)] {
        var rows: [(label: String, utilization: Int?, usedPercent: Int?, resetIn: String?, icon: String, rank: Int)] = [
            (
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
                (
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

        return rows
            .sorted { left, right in
                if left.rank == right.rank {
                    return left.label < right.label
                }
                return left.rank < right.rank
            }
            .map { ($0.label, $0.utilization, $0.usedPercent, $0.resetIn, $0.icon) }
    }

    private var modelBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(usageService.currentUsage.breakdowns.enumerated()), id: \.offset) { entry in
                let metric = entry.element
                HStack {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(metric.label): \(metric.utilization)%")
                        .font(.caption)
                    Spacer()
                    if let resetIn = metric.resetIn {
                        Text(resetIn)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var actionButtons: some View {
        VStack(spacing: 0) {
            Button(action: openDashboard) {
                HStack {
                    Image(systemName: "chart.bar")
                    Text("Open Dashboard")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: refreshUsage) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: { showSettings = true }) {
                HStack {
                    Image(systemName: usageService.authState.needsSession ? "key.fill" : "gear")
                    Text(usageService.authState.needsSession ? (usageService.hasInstalledCodexAuth ? "Auth Options" : "Paste Session") : "Settings")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var quitButton: some View {
        Button(action: quitApp) {
            HStack {
                Image(systemName: "power")
                Text("Quit")
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func usageRow(icon: String, color: Color, label: String, utilization: Int?, resetIn: String?) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            if let utilization {
                Text("\(label): \(utilization)%")
                    .fontWeight(.medium)
            } else {
                Text(label)
                    .fontWeight(.medium)
            }
            Spacer()
            if let resetIn {
                Text(resetIn)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func usageIconName(for utilization: Int?) -> String {
        guard let utilization else { return "chart.pie" }
        if utilization >= 80 { return "exclamationmark.triangle.fill" }
        if utilization >= 50 { return "chart.pie.fill" }
        return "chart.pie"
    }

    private func usageColor(for utilization: Int?) -> Color {
        guard let utilization else { return .primary }
        let criticalThreshold = Int(settingsManager.settings.criticalThreshold)
        let warningThreshold = Int(settingsManager.settings.warningThreshold)
        if utilization >= criticalThreshold { return .red }
        if utilization >= warningThreshold { return .orange }
        return .primary
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
