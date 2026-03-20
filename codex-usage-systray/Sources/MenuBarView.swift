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
        VStack(alignment: .leading, spacing: 6) {
            usageRow(
                icon: usageIconName(for: usageService.currentUsage.primaryUsedPercent),
                color: usageColor(for: usageService.currentUsage.primaryUsedPercent),
                label: usageService.currentUsage.primaryLabel,
                utilization: usageService.currentUsage.primaryUsage,
                resetIn: usageService.currentUsage.primaryResetIn
            )

            if let secondaryLabel = usageService.currentUsage.secondaryLabel {
                usageRow(
                    icon: "calendar",
                    color: usageColor(for: usageService.currentUsage.secondaryUsedPercent),
                    label: secondaryLabel,
                    utilization: usageService.currentUsage.secondaryUsage,
                    resetIn: usageService.currentUsage.secondaryResetIn
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
