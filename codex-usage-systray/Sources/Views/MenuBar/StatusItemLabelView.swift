import SwiftUI

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
