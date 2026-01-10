import Testing
import Foundation
@testable import hyperlink

@Suite("DomainFormatter Tests")
struct DomainFormatterTests {

    @Test("Strips .com TLD")
    func stripsComTLD() {
        let url = URL(string: "https://github.com/user/repo")!
        #expect(DomainFormatter.displayName(for: url) == "github")
    }

    @Test("Strips .org TLD")
    func stripsOrgTLD() {
        let url = URL(string: "https://wikipedia.org/wiki/Swift")!
        #expect(DomainFormatter.displayName(for: url) == "wikipedia")
    }

    @Test("Strips .net TLD")
    func stripsNetTLD() {
        let url = URL(string: "https://dotnet.net/something")!
        #expect(DomainFormatter.displayName(for: url) == "dotnet")
    }

    @Test("Keeps .io TLD")
    func keepsIoTLD() {
        let url = URL(string: "https://example.io/page")!
        #expect(DomainFormatter.displayName(for: url) == "example.io")
    }

    @Test("Keeps .dev TLD")
    func keepsDevTLD() {
        let url = URL(string: "https://web.dev/articles")!
        #expect(DomainFormatter.displayName(for: url) == "web.dev")
    }

    @Test("Extracts apex domain from subdomain")
    func extractsApexFromSubdomain() {
        let url = URL(string: "https://docs.github.com/en/articles")!
        #expect(DomainFormatter.displayName(for: url) == "github")
    }

    @Test("Handles multiple subdomains")
    func handlesMultipleSubdomains() {
        let url = URL(string: "https://api.v2.example.com/endpoint")!
        #expect(DomainFormatter.displayName(for: url) == "example")
    }

    @Test("Handles two-part TLDs")
    func handlesTwoPartTLDs() {
        let url = URL(string: "https://example.co.uk/page")!
        #expect(DomainFormatter.displayName(for: url) == "example.co.uk")
    }

    @Test("Handles simple domain without TLD stripping")
    func handlesSimpleDomain() {
        let url = URL(string: "https://localhost/path")!
        #expect(DomainFormatter.displayName(for: url) == "localhost")
    }

    @Test("Lowercases domain")
    func lowercasesDomain() {
        let url = URL(string: "https://GitHub.COM/user")!
        #expect(DomainFormatter.displayName(for: url) == "github")
    }

    @Test("Returns URL string for URL without host")
    func returnsURLStringForNoHost() {
        let url = URL(string: "file:///path/to/file")!
        #expect(DomainFormatter.displayName(for: url) == "file:///path/to/file")
    }
}
