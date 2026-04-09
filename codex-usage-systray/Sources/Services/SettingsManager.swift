import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }

    private let defaults: UserDefaults
    private let settingsKey: String

    init(
        defaults: UserDefaults = .standard,
        settingsKey: String = "ChatGPTCodexUsageSettings"
    ) {
        self.defaults = defaults
        self.settingsKey = settingsKey

        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
        }
    }

    func setWarningThreshold(_ value: Double) { settings.warningThreshold = value }
    func setCriticalThreshold(_ value: Double) { settings.criticalThreshold = value }
    func setNotificationsEnabled(_ enabled: Bool) { settings.notificationsEnabled = enabled }
    func setCompactDisplay(_ enabled: Bool) { settings.compactDisplay = enabled }
    func resetToDefaults() { settings = AppSettings() }
}
