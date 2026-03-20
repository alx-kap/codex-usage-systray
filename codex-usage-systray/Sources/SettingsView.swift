import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var usageService: UsageService
    @Environment(\.dismiss) private var dismiss

    @State private var warningThreshold: Double = 80
    @State private var criticalThreshold: Double = 90
    @State private var notificationsEnabled: Bool = true
    @State private var compactDisplay: Bool = true
    @State private var sessionCookie: String = ""
    @State private var authMessage: String?
    @State private var authError: String?
    @State private var isSavingSession = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                authSection

                Section("Menu Bar") {
                    Toggle("Compact display (primary · secondary)", isOn: $compactDisplay)
                        .onChange(of: compactDisplay) { newValue in
                            settingsManager.setCompactDisplay(newValue)
                        }
                }

                Section("Notifications") {
                    Toggle("Enable usage alerts", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { newValue in
                            settingsManager.setNotificationsEnabled(newValue)
                        }

                    VStack(alignment: .leading) {
                        Text("Warning threshold: \(Int(warningThreshold))%")
                        Slider(value: $warningThreshold, in: 50...95, step: 5)
                            .onChange(of: warningThreshold) { newValue in
                                settingsManager.setWarningThreshold(newValue)
                            }
                    }

                    VStack(alignment: .leading) {
                        Text("Critical threshold: \(Int(criticalThreshold))%")
                        Slider(value: $criticalThreshold, in: 60...100, step: 5)
                            .onChange(of: criticalThreshold) { newValue in
                                settingsManager.setCriticalThreshold(newValue)
                            }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            footer
        }
        .frame(width: 460, height: 520)
        .onAppear { loadSettings() }
    }

    private var authSection: some View {
        Section("Auth") {
            HStack {
                Image(systemName: authStateIcon)
                    .foregroundColor(authStateColor)
                Text(authStateTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(authStateBadge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(authStateColor.opacity(0.18))
                    .cornerRadius(4)
            }

            if usageService.hasInstalledCodexAuth {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Installed Codex detected")
                        .font(.subheadline.weight(.medium))
                    Text("The app can read your local Codex sign-in and will prefer it automatically. If usage looks stale, reopen Codex and click refresh here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(usageService.installedCodexAuthPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    Button("Refresh Using Installed Codex") {
                        usageService.fetchUsage()
                    }
                }
                .padding(.bottom, 4)
            }

            Text("Manual fallback: open `https://chatgpt.com/codex/settings/usage` in your browser, copy the full `Cookie` request header, then paste it here. Include Cloudflare cookies such as `cf_clearance` if present.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $sessionCookie)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            if let authMessage {
                Text(authMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let authError {
                Text(authError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(isSavingSession ? "Validating…" : (usageService.hasStoredSession ? "Update Fallback Session" : "Save Fallback Session")) {
                    saveSession()
                }
                .disabled(isSavingSession || sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear Fallback Session") {
                    clearSession()
                }
                .disabled(!usageService.hasStoredSession && sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.pie.fill")
                .font(.title)
                .foregroundColor(.green)
            Text("ChatGPT Codex Usage Settings")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Text("Data source: ChatGPT Codex usage dashboard")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Reset to Defaults") { resetToDefaults() }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var authStateIcon: String {
        switch usageService.authState {
        case .configured:
            return "checkmark.shield.fill"
        case .validating:
            return "hourglass"
        case .invalidSession:
            return "exclamationmark.triangle.fill"
        case .missingSession:
            return "key.fill"
        }
    }

    private var authStateColor: Color {
        switch usageService.authState {
        case .configured:
            return .green
        case .validating:
            return .orange
        case .invalidSession:
            return .orange
        case .missingSession:
            return .blue
        }
    }

    private var authStateTitle: String {
        switch usageService.authState {
        case .configured:
            if let source = usageService.activeCredentialSource {
                switch source {
                case .installedCodex:
                    return "Using the ChatGPT auth from your installed Codex app."
                case .storedSessionCookie:
                    return "A validated fallback ChatGPT session is stored in Keychain."
                }
            }
            return "ChatGPT credentials are available."
        case .validating:
            return "Validating the fallback ChatGPT session."
        case .invalidSession:
            return usageService.hasInstalledCodexAuth ? "Installed Codex auth needs refresh." : "The stored fallback ChatGPT session is invalid or expired."
        case .missingSession:
            return usageService.hasInstalledCodexAuth ? "Installed Codex auth is available." : "No ChatGPT credentials detected yet."
        }
    }

    private var authStateBadge: String {
        if usageService.authState == .configured, let source = usageService.activeCredentialSource {
            return source.badgeText
        }

        switch usageService.authState {
        case .configured:
            return "Stored"
        case .validating:
            return "Checking"
        case .invalidSession:
            return "Expired"
        case .missingSession:
            return "Needed"
        }
    }

    private func loadSettings() {
        warningThreshold = settingsManager.settings.warningThreshold
        criticalThreshold = settingsManager.settings.criticalThreshold
        notificationsEnabled = settingsManager.settings.notificationsEnabled
        compactDisplay = settingsManager.settings.compactDisplay
        authMessage = nil
        authError = usageService.error
    }

    private func saveSession() {
        authMessage = nil
        authError = nil
        isSavingSession = true

        Task {
            do {
                try await usageService.saveSessionCookie(sessionCookie)
                await MainActor.run {
                    self.authMessage = "Fallback session stored and validated."
                    self.authError = nil
                    self.isSavingSession = false
                    self.sessionCookie = ""
                }
            } catch {
                await MainActor.run {
                    self.authMessage = nil
                    self.authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isSavingSession = false
                }
            }
        }
    }

    private func clearSession() {
        usageService.clearSessionCookie()
        authMessage = usageService.hasInstalledCodexAuth ? "Fallback session cleared. Installed Codex auth is still available." : "Stored fallback session cleared."
        authError = nil
        sessionCookie = ""
    }

    private func resetToDefaults() {
        settingsManager.resetToDefaults()
        loadSettings()
    }
}
