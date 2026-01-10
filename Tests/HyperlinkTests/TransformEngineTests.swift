import Testing
import Foundation
@testable import hyperlink

@Suite("TransformEngine Tests")
struct TransformEngineTests {

    // MARK: - URL Matching

    @Test("Empty URL match matches all URLs")
    func emptyMatchMatchesAll() {
        let rule = TransformRule(
            name: "Test",
            urlMatch: "",
            transforms: [Transform(target: .title, pattern: "foo", replacement: "bar")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result1 = engine.apply(title: "foo", url: URL(string: "https://example.com")!)
        #expect(result1.title == "bar")

        let result2 = engine.apply(title: "foo", url: URL(string: "https://other.org/page")!)
        #expect(result2.title == "bar")
    }

    @Test("URL prefix matching")
    func urlPrefixMatching() {
        let rule = TransformRule(
            name: "GitHub only",
            urlMatch: "https://github.com",
            transforms: [Transform(target: .title, pattern: "foo", replacement: "bar")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        // Should match github.com URLs
        let result1 = engine.apply(title: "foo", url: URL(string: "https://github.com/user/repo")!)
        #expect(result1.title == "bar")

        // Should not match other URLs
        let result2 = engine.apply(title: "foo", url: URL(string: "https://gitlab.com/user/repo")!)
        #expect(result2.title == "foo")
    }

    // MARK: - Regex Transforms

    @Test("Simple string replacement")
    func simpleStringReplacement() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .title, pattern: "`", replacement: "")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "Hello `World`", url: URL(string: "https://example.com")!)
        #expect(result.title == "Hello World")
    }

    @Test("Regex pattern replacement")
    func regexPatternReplacement() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .title, pattern: #" · [a-z]+/[a-z]+$"#, replacement: "")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "README.md · owner/repo", url: URL(string: "https://github.com")!)
        #expect(result.title == "README.md")
    }

    @Test("Capture group replacement")
    func captureGroupReplacement() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .title, pattern: #"(\w+)@(\w+)"#, replacement: "$1 at $2")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "Contact: user@example", url: URL(string: "https://example.com")!)
        #expect(result.title == "Contact: user at example")
    }

    @Test("Invalid regex is skipped")
    func invalidRegexSkipped() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .title, pattern: "[invalid", replacement: "replaced")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "Original", url: URL(string: "https://example.com")!)
        #expect(result.title == "Original")
    }

    // MARK: - URL Transforms

    @Test("Transform can modify URL")
    func transformCanModifyURL() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .url, pattern: "http://", replacement: "https://")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "Test", url: URL(string: "http://example.com")!)
        #expect(result.url == "https://example.com")
    }

    // MARK: - Execution Order

    @Test("Global rules execute first, then app-specific")
    func executionOrder() {
        let globalRule = TransformRule(
            name: "Global",
            transforms: [Transform(target: .title, pattern: "A", replacement: "B")]
        )
        let appRule = TransformRule(
            name: "App",
            transforms: [Transform(target: .title, pattern: "B", replacement: "C")]
        )
        let appGroup = AppRuleGroup(
            bundleID: "com.test.app",
            displayName: "Test App",
            rules: [appRule]
        )

        let settings = TransformSettings(
            globalGroup: RuleGroup(rules: [globalRule]),
            appGroups: [appGroup]
        )

        // With no target app, only global rules apply
        let engineGlobalOnly = TransformEngine(settings: settings, targetBundleID: nil)
        let result1 = engineGlobalOnly.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result1.title == "B")

        // With target app, both apply in order
        let engineWithApp = TransformEngine(settings: settings, targetBundleID: "com.test.app")
        let result2 = engineWithApp.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result2.title == "C")  // A -> B (global) -> C (app)
    }

    @Test("Multiple transforms in a rule execute in order")
    func multipleTransformsInOrder() {
        let rule = TransformRule(
            name: "Test",
            transforms: [
                Transform(target: .title, pattern: "A", replacement: "B"),
                Transform(target: .title, pattern: "B", replacement: "C")
            ]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result.title == "C")  // A -> B -> C
    }

    @Test("Multiple rules execute in order")
    func multipleRulesInOrder() {
        let rule1 = TransformRule(
            name: "Rule1",
            transforms: [Transform(target: .title, pattern: "A", replacement: "B")]
        )
        let rule2 = TransformRule(
            name: "Rule2",
            transforms: [Transform(target: .title, pattern: "B", replacement: "C")]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule1, rule2]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result.title == "C")  // A -> B (rule1) -> C (rule2)
    }

    // MARK: - Disabled Rules/Transforms

    @Test("Disabled rules are skipped")
    func disabledRulesSkipped() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .title, pattern: "A", replacement: "B")],
            isEnabled: false
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result.title == "A")  // No change
    }

    @Test("Disabled transforms are skipped")
    func disabledTransformsSkipped() {
        let rule = TransformRule(
            name: "Test",
            transforms: [Transform(target: .title, pattern: "A", replacement: "B", isEnabled: false)]
        )
        let settings = TransformSettings(globalGroup: RuleGroup(rules: [rule]))
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result.title == "A")  // No change
    }

    @Test("Disabled app groups are skipped")
    func disabledAppGroupsSkipped() {
        let appRule = TransformRule(
            name: "App",
            transforms: [Transform(target: .title, pattern: "A", replacement: "B")]
        )
        let appGroup = AppRuleGroup(
            bundleID: "com.test.app",
            displayName: "Test App",
            rules: [appRule],
            isEnabled: false
        )

        let settings = TransformSettings(
            globalGroup: RuleGroup(rules: []),
            appGroups: [appGroup]
        )

        let engine = TransformEngine(settings: settings, targetBundleID: "com.test.app")
        let result = engine.apply(title: "A", url: URL(string: "https://example.com")!)
        #expect(result.title == "A")  // No change, app group disabled
    }

    // MARK: - Pattern Validation

    @Test("validatePattern returns nil for valid patterns")
    func validatePatternValid() {
        #expect(TransformEngine.validatePattern("hello") == nil)
        #expect(TransformEngine.validatePattern("[a-z]+") == nil)
        #expect(TransformEngine.validatePattern(#"\d{3}-\d{4}"#) == nil)
        #expect(TransformEngine.validatePattern("") == nil)
    }

    @Test("validatePattern returns error for invalid patterns")
    func validatePatternInvalid() {
        #expect(TransformEngine.validatePattern("[invalid") != nil)
        #expect(TransformEngine.validatePattern("(unclosed") != nil)
        #expect(TransformEngine.validatePattern("*invalid") != nil)
    }

    // MARK: - Default Settings

    @Test("Default settings have expected rules")
    func defaultSettingsHaveExpectedRules() {
        let settings = TransformSettings.defaultSettings()

        #expect(settings.globalGroup.rules.count == 2)
        #expect(settings.globalGroup.rules[0].name == "Strip backticks")
        #expect(settings.globalGroup.rules[1].name == "GitHub suffix")
        #expect(settings.appGroups.isEmpty)
    }

    @Test("Default settings strip backticks")
    func defaultSettingsStripBackticks() {
        let settings = TransformSettings.defaultSettings()
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "Hello `World`", url: URL(string: "https://example.com")!)
        #expect(result.title == "Hello World")
    }

    @Test("Default settings trim GitHub suffix")
    func defaultSettingsTrimGitHubSuffix() {
        let settings = TransformSettings.defaultSettings()
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "README.md · owner/repo", url: URL(string: "https://github.com/owner/repo")!)
        #expect(result.title == "README.md")
    }

    @Test("Default settings don't trim non-GitHub suffix")
    func defaultSettingsDontTrimNonGitHub() {
        let settings = TransformSettings.defaultSettings()
        let engine = TransformEngine(settings: settings)

        let result = engine.apply(title: "Page · owner/repo", url: URL(string: "https://example.com")!)
        #expect(result.title == "Page · owner/repo")
    }

    // MARK: - Migration

    @Test("Migration with both options enabled")
    func migrationBothEnabled() {
        let settings = TransformSettings.migrateFromLegacy(removeBackticks: true, trimGitHubSuffix: true)

        #expect(settings.globalGroup.rules.count == 2)
        #expect(settings.globalGroup.rules[0].name == "Strip backticks")
        #expect(settings.globalGroup.rules[1].name == "GitHub suffix")
    }

    @Test("Migration with only backticks enabled")
    func migrationBackticksOnly() {
        let settings = TransformSettings.migrateFromLegacy(removeBackticks: true, trimGitHubSuffix: false)

        #expect(settings.globalGroup.rules.count == 1)
        #expect(settings.globalGroup.rules[0].name == "Strip backticks")
    }

    @Test("Migration with both options disabled")
    func migrationBothDisabled() {
        let settings = TransformSettings.migrateFromLegacy(removeBackticks: false, trimGitHubSuffix: false)

        #expect(settings.globalGroup.rules.isEmpty)
    }
}
