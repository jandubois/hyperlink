import AppKit

/// State of title fetching for an extracted link
enum TitleFetchState: Sendable {
    case pending
    case fetching
    case success
    case failed
}

/// A link extracted from a page
struct ExtractedLink: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let anchorText: String?
    var fetchedTitle: String?
    var titleFetchState: TitleFetchState

    init(url: URL, anchorText: String?) {
        self.id = UUID()
        self.url = url
        self.anchorText = anchorText
        self.fetchedTitle = nil
        self.titleFetchState = .pending
    }

    /// The title to display (fetched title, anchor text, or URL)
    var displayTitle: String {
        fetchedTitle ?? anchorText ?? url.absoluteString
    }

    /// Whether the displayed title is provisional (not the fetched title)
    var isTitleProvisional: Bool {
        fetchedTitle == nil && titleFetchState != .success
    }
}

/// A pseudo-browser representing links extracted from a page
@MainActor
final class ExtractedLinksSource: ObservableObject, Identifiable {
    let id: UUID
    let sourceURL: URL
    let sourceTitle: String
    @Published var links: [ExtractedLink]
    @Published var favicon: NSImage?

    /// Display name derived from the source URL's domain
    var displayName: String {
        DomainFormatter.displayName(for: sourceURL)
    }

    init(sourceURL: URL, sourceTitle: String, links: [ExtractedLink]) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.links = links
        self.favicon = nil
    }

    /// Creates an ExtractedLinksSource from parsed HTML links
    static func create(
        from parsedLinks: [HTMLLinkParser.ParsedLink],
        sourceURL: URL,
        sourceTitle: String
    ) -> ExtractedLinksSource {
        let links = parsedLinks.map { parsed in
            ExtractedLink(url: parsed.url, anchorText: parsed.anchorText)
        }
        return ExtractedLinksSource(
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            links: links
        )
    }

    /// Starts fetching titles for all links
    func startTitleFetching() {
        let fetcher = TitleFetcher()

        for index in links.indices {
            links[index].titleFetchState = .fetching
        }

        // Launch all fetches concurrently
        for index in links.indices {
            let url = links[index].url
            Task {
                let title = await fetcher.fetchTitle(from: url)
                await MainActor.run {
                    guard index < self.links.count,
                          self.links[index].url == url else {
                        return
                    }
                    if let title = title {
                        self.links[index].fetchedTitle = title
                        self.links[index].titleFetchState = .success
                    } else {
                        self.links[index].titleFetchState = .failed
                    }
                }
            }
        }
    }

    /// Fetches the favicon for the source URL
    func fetchFavicon() {
        guard let host = sourceURL.host,
              let faviconURL = URL(string: "https://\(host)/favicon.ico") else {
            return
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: faviconURL)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode),
                   let image = NSImage(data: data) {
                    await MainActor.run {
                        self.favicon = image
                    }
                }
            } catch {
                // Favicon fetch failed, use default icon
            }
        }
    }

    /// Converts links to TabInfo for display in the existing tab list
    func asWindowInfo() -> WindowInfo {
        let tabs = links.enumerated().map { index, link in
            TabInfo(
                index: index + 1,
                title: link.displayTitle,
                url: link.url,
                isActive: index == 0
            )
        }
        return WindowInfo(index: 1, name: "Extracted from \(sourceTitle)", tabs: tabs)
    }
}
