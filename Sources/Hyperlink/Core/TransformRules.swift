import Foundation

/// Target field for a transform (title or URL)
enum TransformTarget: String, Codable, CaseIterable, Sendable {
    case title
    case url
}

/// A single regex-based transform
struct Transform: Codable, Identifiable, Sendable {
    var id: UUID
    var target: TransformTarget
    var pattern: String
    var replacement: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        target: TransformTarget = .title,
        pattern: String = "",
        replacement: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.target = target
        self.pattern = pattern
        self.replacement = replacement
        self.isEnabled = isEnabled
    }
}

/// A rule that matches URLs and applies transforms
struct TransformRule: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var urlMatch: String  // empty = match all URLs
    var transforms: [Transform]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        urlMatch: String = "",
        transforms: [Transform] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.urlMatch = urlMatch
        self.transforms = transforms
        self.isEnabled = isEnabled
    }
}

/// A group of rules (used for global rules)
struct RuleGroup: Codable, Sendable {
    var rules: [TransformRule]

    init(rules: [TransformRule] = []) {
        self.rules = rules
    }
}

/// An app-specific group of rules
struct AppRuleGroup: Codable, Identifiable, Sendable {
    var id: UUID
    var bundleID: String
    var displayName: String
    var rules: [TransformRule]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        bundleID: String,
        displayName: String,
        rules: [TransformRule] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.rules = rules
        self.isEnabled = isEnabled
    }
}

/// All transformation settings
struct TransformSettings: Codable, Sendable {
    var globalGroup: RuleGroup
    var appGroups: [AppRuleGroup]

    init(globalGroup: RuleGroup = RuleGroup(), appGroups: [AppRuleGroup] = []) {
        self.globalGroup = globalGroup
        self.appGroups = appGroups
    }

    /// Default settings with rules migrated from legacy TitleTransform
    static func defaultSettings() -> TransformSettings {
        TransformSettings(
            globalGroup: RuleGroup(rules: [
                // Strip backticks (applies to all URLs)
                TransformRule(
                    name: "Strip backticks",
                    urlMatch: "",
                    transforms: [
                        Transform(target: .title, pattern: "`", replacement: "")
                    ]
                ),
                // GitHub suffix (applies only to github.com)
                TransformRule(
                    name: "GitHub suffix",
                    urlMatch: "https://github.com",
                    transforms: [
                        Transform(
                            target: .title,
                            pattern: #" [·\-] [a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$"#,
                            replacement: ""
                        )
                    ]
                )
            ]),
            appGroups: []
        )
    }

    /// Migrate from legacy boolean settings
    static func migrateFromLegacy(removeBackticks: Bool, trimGitHubSuffix: Bool) -> TransformSettings {
        var rules: [TransformRule] = []

        if removeBackticks {
            rules.append(TransformRule(
                name: "Strip backticks",
                urlMatch: "",
                transforms: [
                    Transform(target: .title, pattern: "`", replacement: "")
                ]
            ))
        }

        if trimGitHubSuffix {
            rules.append(TransformRule(
                name: "GitHub suffix",
                urlMatch: "https://github.com",
                transforms: [
                    Transform(
                        target: .title,
                        pattern: #" [·\-] [a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$"#,
                        replacement: ""
                    )
                ]
            ))
        }

        return TransformSettings(
            globalGroup: RuleGroup(rules: rules),
            appGroups: []
        )
    }
}
