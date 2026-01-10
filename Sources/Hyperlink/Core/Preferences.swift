import Foundation

/// Application preferences stored in UserDefaults
/// Thread-safe via UserDefaults which is itself thread-safe
final class Preferences: ObservableObject, @unchecked Sendable {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let removeBackticks = "removeBackticks"
        static let trimGitHubSuffix = "trimGitHubSuffix"
        static let multiSelectionFormat = "multiSelectionFormat"
        static let transformRules = "transformRules"
        static let didMigrateLegacyTransforms = "didMigrateLegacyTransforms"
    }

    // MARK: - Transform Settings

    @Published var transformSettings: TransformSettings {
        didSet { saveTransformSettings() }
    }

    // MARK: - Multi-Selection Settings

    @Published var multiSelectionFormat: MultiSelectionFormat {
        didSet { defaults.set(multiSelectionFormat.rawValue, forKey: Keys.multiSelectionFormat) }
    }

    private init() {
        // Register defaults
        defaults.register(defaults: [
            Keys.removeBackticks: true,
            Keys.trimGitHubSuffix: true,
            Keys.multiSelectionFormat: MultiSelectionFormat.list.rawValue
        ])

        // Load multi-selection format
        if let formatString = defaults.string(forKey: Keys.multiSelectionFormat),
           let format = MultiSelectionFormat(rawValue: formatString) {
            self.multiSelectionFormat = format
        } else {
            self.multiSelectionFormat = .list
        }

        // Load or migrate transform settings
        self.transformSettings = TransformSettings()  // Temporary, will be overwritten
        self.transformSettings = loadTransformSettings()
    }

    private func loadTransformSettings() -> TransformSettings {
        // Check if we have existing transform rules
        if let data = defaults.data(forKey: Keys.transformRules),
           let settings = try? JSONDecoder().decode(TransformSettings.self, from: data) {
            return settings
        }

        // Check if we need to migrate legacy settings
        if !defaults.bool(forKey: Keys.didMigrateLegacyTransforms) {
            let removeBackticks = defaults.bool(forKey: Keys.removeBackticks)
            let trimGitHubSuffix = defaults.bool(forKey: Keys.trimGitHubSuffix)

            // Only migrate if at least one legacy key was explicitly set
            let hasLegacySettings = defaults.object(forKey: Keys.removeBackticks) != nil ||
                                    defaults.object(forKey: Keys.trimGitHubSuffix) != nil

            if hasLegacySettings {
                let settings = TransformSettings.migrateFromLegacy(
                    removeBackticks: removeBackticks,
                    trimGitHubSuffix: trimGitHubSuffix
                )
                defaults.set(true, forKey: Keys.didMigrateLegacyTransforms)
                saveTransformSettingsSync(settings)
                return settings
            }
        }

        // Return default settings for fresh install
        let settings = TransformSettings.defaultSettings()
        saveTransformSettingsSync(settings)
        return settings
    }

    private func saveTransformSettings() {
        saveTransformSettingsSync(transformSettings)
    }

    private func saveTransformSettingsSync(_ settings: TransformSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Keys.transformRules)
        }
    }

    /// Legacy compatibility: Get current transform settings as TitleTransform
    /// This checks if the default rules are enabled to maintain backward compatibility
    var titleTransform: TitleTransform {
        // Check if backtick rule exists and is enabled
        let hasBacktickRule = transformSettings.globalGroup.rules.contains { rule in
            rule.isEnabled && rule.name == "Strip backticks"
        }

        // Check if GitHub suffix rule exists and is enabled
        let hasGitHubRule = transformSettings.globalGroup.rules.contains { rule in
            rule.isEnabled && rule.name == "GitHub suffix"
        }

        return TitleTransform(
            removeBackticks: hasBacktickRule,
            trimGitHubSuffix: hasGitHubRule
        )
    }
}
