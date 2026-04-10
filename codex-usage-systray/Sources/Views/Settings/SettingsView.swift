import AppKit
import SwiftUI

private enum SettingsVisualTokens {
    static let contentWidth: CGFloat = 472
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 18
    static let cardPadding: CGFloat = 16
}

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var usageService: UsageService

    @State private var warningThreshold: Double = 80
    @State private var criticalThreshold: Double = 90
    @State private var notificationsEnabled = true
    @State private var compactDisplay = true
    @State private var sessionCookie = ""
    @State private var authMessage: String?
    @State private var authError: String?
    @State private var isSavingSession = false

    var body: some View {
        settingsBody
            .frame(width: SettingsVisualTokens.contentWidth, alignment: .topLeading)
            .frame(minHeight: 540, alignment: .topLeading)
            .modifier(SettingsToolbarGlassModifier())
            .background(SettingsWindowAccessor())
            .onAppear(perform: loadSettings)
    }

    @ViewBuilder
    private var settingsBody: some View {
        if #available(macOS 26.0, *) {
            ScrollView {
                GlassEffectContainer(spacing: SettingsVisualTokens.sectionSpacing) {
                    settingsContent
                }
                .padding(.horizontal, SettingsVisualTokens.horizontalPadding)
                .padding(.vertical, SettingsVisualTokens.verticalPadding)
            }
            .modifier(SettingsWindowBackgroundModifier())
            .background(settingsBackdrop)
        } else {
            ScrollView {
                settingsContent
                    .padding(.horizontal, SettingsVisualTokens.horizontalPadding)
                    .padding(.vertical, SettingsVisualTokens.verticalPadding)
            }
            .modifier(SettingsWindowBackgroundModifier())
            .background(settingsBackdrop)
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsVisualTokens.sectionSpacing) {
            authSection
            displaySection
            notificationsSection

            Text("This app intentionally stays a lightweight macOS menu bar utility. Usage comes from the ChatGPT Codex usage dashboard.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            HStack {
                Spacer()

                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
    }

    private var settingsBackdrop: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.12),
                Color.clear,
                Color.primary.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var authSection: some View {
        SettingsSectionCard(title: "Authentication") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: authStateIcon)
                        .foregroundStyle(authStateColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(authStateTitle)
                            .font(.body)
                        Text(authStateSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(authStateBadge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(authStateColor)
                }

                if usageService.hasInstalledCodexAuth {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Installed Codex detected")
                            .font(.subheadline.weight(.medium))
                        Text(usageService.installedCodexAuthPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Button("Refresh Using Installed Codex") {
                            usageService.fetchUsage()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                Text("Manual fallback: open `https://chatgpt.com/codex/settings/usage` in your browser, copy the full `Cookie` request header, then paste it here. Include Cloudflare cookies such as `cf_clearance` if present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $sessionCookie)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)

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
                    Button(isSavingSession ? "Validating…" : saveButtonTitle) {
                        saveSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingSession || sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Fallback Session") {
                        clearSession()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!usageService.hasStoredSession && sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displaySection: some View {
        SettingsSectionCard(title: "Menu Bar") {
            Toggle("Compact display (primary · secondary)", isOn: $compactDisplay)
                .onChange(of: compactDisplay) { newValue in
                    settingsManager.setCompactDisplay(newValue)
                }
        }
    }

    private var notificationsSection: some View {
        SettingsSectionCard(title: "Notifications") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable usage alerts", isOn: $notificationsEnabled)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.medium))
            }

            Slider(value: value, in: range, step: 5)
                .onChange(of: value.wrappedValue, perform: onChange)
        }
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
        case .validating, .invalidSession:
            return .orange
        case .missingSession:
            return .accentColor
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
            return usageService.hasInstalledCodexAuth
                ? "Installed Codex auth needs refresh."
                : "The stored fallback ChatGPT session is invalid or expired."
        case .missingSession:
            return usageService.hasInstalledCodexAuth
                ? "Installed Codex auth is available."
                : "No ChatGPT credentials detected yet."
        }
    }

    private var authStateSubtitle: String {
        if usageService.hasInstalledCodexAuth {
            return "The app prefers your local Codex desktop sign-in and falls back to a stored browser session only when needed."
        }
        return "If local Codex auth is unavailable, you can store a validated Cookie header fallback in Keychain."
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

    private var saveButtonTitle: String {
        usageService.hasStoredSession ? "Update Fallback Session" : "Save Fallback Session"
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
                    authMessage = "Fallback session stored and validated."
                    authError = nil
                    isSavingSession = false
                    sessionCookie = ""
                }
            } catch {
                await MainActor.run {
                    authMessage = nil
                    authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isSavingSession = false
                }
            }
        }
    }

    private func clearSession() {
        usageService.clearSessionCookie()
        authMessage = usageService.hasInstalledCodexAuth
            ? "Fallback session cleared. Installed Codex auth is still available."
            : "Stored fallback session cleared."
        authError = nil
        sessionCookie = ""
    }

    private func resetToDefaults() {
        settingsManager.resetToDefaults()
        loadSettings()
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ObserverView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ObserverView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window {
            SettingsWindowController.shared.register(window: window)
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SettingsVisualTokens.cardPadding)
            .settingsCardBackground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func settingsCardBackground() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: SettingsVisualTokens.cardCornerRadius,
            style: .continuous
        )

        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

private struct SettingsWindowBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.thinMaterial, for: .window)
        } else {
            content
        }
    }
}

private struct SettingsToolbarGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}
