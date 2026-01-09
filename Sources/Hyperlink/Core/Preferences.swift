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
    }

    // MARK: - Transform Settings

    @Published var removeBackticks: Bool {
        didSet { defaults.set(removeBackticks, forKey: Keys.removeBackticks) }
    }

    @Published var trimGitHubSuffix: Bool {
        didSet { defaults.set(trimGitHubSuffix, forKey: Keys.trimGitHubSuffix) }
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

        // Load values from defaults
        self.removeBackticks = defaults.bool(forKey: Keys.removeBackticks)
        self.trimGitHubSuffix = defaults.bool(forKey: Keys.trimGitHubSuffix)

        if let formatString = defaults.string(forKey: Keys.multiSelectionFormat),
           let format = MultiSelectionFormat(rawValue: formatString) {
            self.multiSelectionFormat = format
        } else {
            self.multiSelectionFormat = .list
        }
    }

    /// Get current transform settings
    var titleTransform: TitleTransform {
        TitleTransform(
            removeBackticks: removeBackticks,
            trimGitHubSuffix: trimGitHubSuffix
        )
    }
}
