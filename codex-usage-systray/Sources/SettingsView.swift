import SwiftUI

fileprivate enum SettingsVisualTokens {
    static let windowSize = CGSize(width: 460, height: 520)
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 10
    static let outerHorizontalPadding: CGFloat = 12
    static let outerTopPadding: CGFloat = 8
    static let outerBottomPadding: CGFloat = 10
    static let cardPadding: CGFloat = 11
    static let cardSpacing: CGFloat = 9
    static let sectionSpacing: CGFloat = 8
    static let dividerOpacity: Double = 0.11
    static let hoverOpacity: Double = 0.11
    static let pressedOpacity: Double = 0.16
}

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var usageService: UsageService
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var warningThreshold: Double = 80
    @State private var criticalThreshold: Double = 90
    @State private var notificationsEnabled: Bool = true
    @State private var compactDisplay: Bool = true
    @State private var sessionCookie: String = ""
    @State private var authMessage: String?
    @State private var authError: String?
    @State private var isSavingSession = false

    init(
        settingsManager: SettingsManager,
        usageService: UsageService,
        onClose: (() -> Void)? = nil
    ) {
        self._settingsManager = ObservedObject(wrappedValue: settingsManager)
        self._usageService = ObservedObject(wrappedValue: usageService)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: SettingsVisualTokens.cardSpacing) {
                    authSection
                    menuBarSection
                    notificationsSection
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 1)
            }

            footer
        }
        .padding(.horizontal, SettingsVisualTokens.outerHorizontalPadding)
        .padding(.top, SettingsVisualTokens.outerTopPadding)
        .padding(.bottom, SettingsVisualTokens.outerBottomPadding)
        .frame(width: SettingsVisualTokens.windowSize.width, height: SettingsVisualTokens.windowSize.height)
        .onAppear { loadSettings() }
    }

    private var authSection: some View {
        sectionCard("Auth") {
            VStack(alignment: .leading, spacing: SettingsVisualTokens.sectionSpacing) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: authStateIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(authStateColor)
                        .frame(width: 15)

                    Text(authStateTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Text(authStateBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(authStateColor.opacity(0.15))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(authStateColor.opacity(0.24), lineWidth: 0.8)
                                )
                        )
                }

                if usageService.hasInstalledCodexAuth {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Installed Codex detected")
                            .font(.subheadline.weight(.medium))
                        Text("The app can read your local Codex sign-in and will prefer it automatically. If usage looks stale, reopen Codex and click refresh here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(usageService.installedCodexAuthPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Button("Refresh Using Installed Codex") {
                            usageService.fetchUsage()
                        }
                        .buttonStyle(SettingsGlassButtonStyle(role: .normal))
                    }
                    .padding(9)
                    .background(subtleInsetBackground)
                }

                divider

                Text("Manual fallback: open `https://chatgpt.com/codex/settings/usage` in your browser, copy the full `Cookie` request header, then paste it here. Include Cloudflare cookies such as `cf_clearance` if present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $sessionCookie)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(4)
                    .background(subtleInsetBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )

                if let authMessage {
                    Text(authMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(isSavingSession ? "Validating…" : (usageService.hasStoredSession ? "Update Fallback Session" : "Save Fallback Session")) {
                        saveSession()
                    }
                    .buttonStyle(SettingsGlassButtonStyle(role: .normal))
                    .disabled(isSavingSession || sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Fallback Session") {
                        clearSession()
                    }
                    .buttonStyle(SettingsGlassButtonStyle(role: .subtle))
                    .disabled(!usageService.hasStoredSession && sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var menuBarSection: some View {
        sectionCard("Menu Bar") {
            Toggle("Compact display (primary · secondary)", isOn: $compactDisplay)
                .toggleStyle(.switch)
                .onChange(of: compactDisplay) { newValue in
                    settingsManager.setCompactDisplay(newValue)
                }
        }
    }

    private var notificationsSection: some View {
        sectionCard("Notifications") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable usage alerts", isOn: $notificationsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: notificationsEnabled) { newValue in
                        settingsManager.setNotificationsEnabled(newValue)
                    }

                sliderRow(
                    title: "Warning threshold",
                    valueText: "\(Int(warningThreshold))%",
                    value: $warningThreshold,
                    range: 50...95
                ) { newValue in
                    settingsManager.setWarningThreshold(newValue)
                }

                sliderRow(
                    title: "Critical threshold",
                    valueText: "\(Int(criticalThreshold))%",
                    value: $criticalThreshold,
                    range: 60...100
                ) { newValue in
                    settingsManager.setCriticalThreshold(newValue)
                }
            }
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: 5)
                .onChange(of: value.wrappedValue, perform: onChange)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green.opacity(0.16))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                )
            Text("ChatGPT Codex Usage Settings")
                .font(.headline)
            Spacer()
            Button(action: closeSettings) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 23, height: 23)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                            .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 0.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.top, 0)
    }

    private var footer: some View {
        HStack {
            Text("Data source: ChatGPT Codex usage dashboard")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset to Defaults") { resetToDefaults() }
                .buttonStyle(SettingsGlassButtonStyle(role: .danger))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 2)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(SettingsVisualTokens.dividerOpacity))
            .frame(height: 0.8)
    }

    private var subtleInsetBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.018))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
            )
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
        .padding(SettingsVisualTokens.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsVisualTokens.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.008))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsVisualTokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
                )
        )
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

    private func closeSettings() {
        if let onClose {
            onClose()
            return
        }
        dismiss()
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

private struct SettingsGlassButtonStyle: ButtonStyle {
    enum Role {
        case normal
        case subtle
        case danger
    }

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        SettingsGlassButtonBody(configuration: configuration, role: role)
    }
}

private struct SettingsGlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: SettingsGlassButtonStyle.Role
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.controlCornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsVisualTokens.controlCornerRadius, style: .continuous)
                            .strokeBorder(strokeColor, lineWidth: 0.8)
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
            return baseTint.opacity(SettingsVisualTokens.pressedOpacity)
        }
        if isHovered {
            return baseTint.opacity(SettingsVisualTokens.hoverOpacity)
        }
        return Color.white.opacity(0.055)
    }

    private var strokeColor: Color {
        if isHovered || configuration.isPressed {
            return baseTint.opacity(0.4)
        }
        return Color.white.opacity(0.18)
    }

    private var baseTint: Color {
        switch role {
        case .normal:
            return .primary
        case .subtle:
            return .secondary
        case .danger:
            return .red
        }
    }
}
