import Testing
@testable import Hyperlink

@Suite("TitleTransform Tests")
struct TitleTransformTests {

    @Test("Remove backticks from title")
    func removeBackticks() {
        let transform = TitleTransform(removeBackticks: true, trimGitHubSuffix: false)

        #expect(transform.apply(to: "Hello `World`") == "Hello World")
        #expect(transform.apply(to: "`code`") == "code")
        #expect(transform.apply(to: "No backticks here") == "No backticks here")
        #expect(transform.apply(to: "```multiple```") == "multiple")
    }

    @Test("Keep backticks when disabled")
    func keepBackticks() {
        let transform = TitleTransform(removeBackticks: false, trimGitHubSuffix: false)

        #expect(transform.apply(to: "Hello `World`") == "Hello `World`")
    }

    @Test("Trim GitHub suffix with dot separator")
    func trimGitHubSuffixDot() {
        let transform = TitleTransform(removeBackticks: false, trimGitHubSuffix: true)

        #expect(transform.apply(to: "README.md · owner/repo") == "README.md")
        #expect(transform.apply(to: "Pull Request #123 · my-org/my-project") == "Pull Request #123")
        #expect(transform.apply(to: "Issues · user123/some_repo.swift") == "Issues")
    }

    @Test("Trim GitHub suffix with dash separator")
    func trimGitHubSuffixDash() {
        let transform = TitleTransform(removeBackticks: false, trimGitHubSuffix: true)

        #expect(transform.apply(to: "README.md - owner/repo") == "README.md")
    }

    @Test("Keep non-GitHub suffixes")
    func keepNonGitHubSuffix() {
        let transform = TitleTransform(removeBackticks: false, trimGitHubSuffix: true)

        #expect(transform.apply(to: "Some Article - Website") == "Some Article - Website")
        #expect(transform.apply(to: "Page · Not a repo") == "Page · Not a repo")
    }

    @Test("Default transform applies all")
    func defaultTransform() {
        let transform = TitleTransform.default

        #expect(transform.apply(to: "`Feature` PR · owner/repo") == "Feature PR")
    }

    @Test("None transform keeps original")
    func noneTransform() {
        let transform = TitleTransform.none

        #expect(transform.apply(to: "`Feature` PR · owner/repo") == "`Feature` PR · owner/repo")
    }
}
