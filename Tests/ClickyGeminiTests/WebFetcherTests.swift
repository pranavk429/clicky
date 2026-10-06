import XCTest
@testable import ClickyGemini

/// Fixture-based tests for the pure web-extraction parsers. No network here:
/// the async tests exercise only the pre-flight validation in `WebFetcher`.
final class WebFetcherTests: XCTestCase {

    // MARK: HTML extraction

    func testHTMLToTextExtractsTitleStripsScriptsAndDecodesEntities() {
        let html = """
        <!DOCTYPE html>
        <html><head>
        <title>Clicky &amp; You</title>
        <style>body { color: red; }</style>
        <script>console.log("ignore &amp; me");</script>
        <noscript>Enable JavaScript to continue.</noscript>
        </head>
        <body>
        <h1>World news</h1>
        <p>Alpha&nbsp;&mdash; beta &#8364; &amp;amp; gamma.</p>
        <!-- secret comment -->
        <p>Delta <b>bold</b> epsilon.</p>
        </body></html>
        """
        let result = WebFetcher.htmlToText(html)
        XCTAssertEqual(result.title, "Clicky & You")
        XCTAssertEqual(result.text, "Clicky & You World news Alpha — beta € &amp; gamma. Delta bold epsilon.")
    }

    func testHTMLToTextTruncatesToMaxCharacters() {
        let result = WebFetcher.htmlToText("<p>0123456789</p>", maxCharacters: 5)
        XCTAssertEqual(result.text, "01234")
    }

    func testHTMLToTextReturnsNilTitleWhenAbsent() {
        let result = WebFetcher.htmlToText("<p>Just text.</p>")
        XCTAssertNil(result.title)
        XCTAssertEqual(result.text, "Just text.")
    }

    // MARK: Feed extraction

    func testRSSToLinesExtractsReadableItems() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title><![CDATA[Example News]]></title>
          <item>
            <title>First &amp; Foremost</title>
            <description><![CDATA[<p>Alpha <b>beta</b> gamma.</p>]]></description>
          </item>
          <item>
            <title>Second Story</title>
            <description>Plain text &amp; details.</description>
          </item>
          <item>
            <title>Third</title>
          </item>
        </channel></rss>
        """
        let feed = WebFetcher.rssToLines(xml)
        XCTAssertEqual(feed.title, "Example News")
        XCTAssertEqual(feed.lines, [
            "First & Foremost — Alpha beta gamma.",
            "Second Story — Plain text & details.",
            "Third",
        ])
    }

    // MARK: Response routing

    func testContentKindClassifiesCommonMimeTypes() {
        XCTAssertEqual(WebFetcher.contentKind(mimeType: "text/html; charset=utf-8", body: "<html>"), .html)
        XCTAssertEqual(WebFetcher.contentKind(mimeType: "application/rss+xml", body: "<rss>"), .feed)
        XCTAssertEqual(WebFetcher.contentKind(mimeType: "application/atom+xml", body: "<feed>"), .feed)
        XCTAssertEqual(WebFetcher.contentKind(mimeType: "text/plain", body: "hello"), .plain)
        XCTAssertEqual(WebFetcher.contentKind(mimeType: nil, body: "<?xml version=\"1.0\"?><rss>"), .feed)
        XCTAssertEqual(WebFetcher.contentKind(mimeType: nil, body: "<html>"), .html)
    }

    // MARK: DuckDuckGo parsing

    func testParseDuckDuckGoExtractsResultsAndUnwrapsRedirect() {
        let html = """
        <html><body>
        <table>
          <tr><td valign="top">1.&nbsp;</td>
              <td><a rel="nofollow" href="https://example.com/world-news" class='result-link'>World &amp; News Today</a></td></tr>
          <tr><td>&nbsp;</td>
              <td class="result-snippet">Latest &lt;headlines&gt; from around the globe.</td></tr>
          <tr><td valign="top">2.&nbsp;</td>
              <td><a rel="nofollow" class="result-link" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fnews.example.org%2Fstory%3Fid%3D7&amp;rut=abc">Example Story</a></td></tr>
          <tr><td>&nbsp;</td>
              <td class="result-snippet">A &amp; B <b>details</b> here.</td></tr>
        </table>
        </body></html>
        """
        let results = WebFetcher.parseDuckDuckGo(html, maxResults: 5)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "World & News Today")
        XCTAssertEqual(results[0].url.absoluteString, "https://example.com/world-news")
        XCTAssertEqual(results[0].snippet, "Latest <headlines> from around the globe.")
        XCTAssertEqual(results[1].title, "Example Story")
        XCTAssertEqual(results[1].url.absoluteString, "https://news.example.org/story?id=7")
        XCTAssertEqual(results[1].snippet, "A & B details here.")
    }

    func testParseDuckDuckGoFallsBackToPlainExternalAnchors() {
        let html = #"<html><body><a href="https://example.com/page">Example page</a><a href="https://duckduckgo.com/settings">Settings</a></body></html>"#
        let results = WebFetcher.parseDuckDuckGo(html, maxResults: 5)
        XCTAssertEqual(results.map(\.url.absoluteString), ["https://example.com/page"])
    }

    func testParseDuckDuckGoReturnsEmptyForGarbage() {
        XCTAssertTrue(WebFetcher.parseDuckDuckGo("<html><body><p>No results.</p></body></html>").isEmpty)
    }

    func testSearchResultURLRejectsNonHTTPSchemes() {
        XCTAssertNil(WebFetcher.searchResultURL(fromHref: "javascript:alert(1)"))
        XCTAssertNil(WebFetcher.searchResultURL(fromHref: "file:///etc/passwd"))
        XCTAssertNil(WebFetcher.searchResultURL(fromHref: ""))
    }

    // MARK: Pre-flight validation (no network is reached)

    func testFetchRejectsNonHTTPSchemeWithoutNetwork() async {
        let fetcher = WebFetcher()
        await assertWebError(.invalidURL) {
            _ = try await fetcher.fetch(url: URL(string: "file:///etc/passwd")!)
        }
    }

    func testSearchRejectsEmptyQueryWithoutNetwork() async {
        let fetcher = WebFetcher()
        await assertWebError(.invalidURL) {
            _ = try await fetcher.search(query: "   ")
        }
    }

    // MARK: Private-host guard (SSRF)

    func testPrivateHostGuardCoversLoopbackLocalAndPrivateLiterals() {
        for host in ["localhost", "LOCALHOST", "app.localhost", "printer.local",
                     "127.0.0.1", "127.255.254.253", "10.1.2.3", "172.16.0.1", "172.31.255.255",
                     "192.168.0.1", "169.254.10.20", "::1", "[::1]", "fe80::1", "fe80::abcd:1234",
                     "::ffff:127.0.0.1", "::ffff:192.168.1.5"] {
            XCTAssertTrue(WebFetcher.isPrivateHost(host), "\(host) must be treated as private")
        }
        for host in ["example.com", "8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.0.1",
                     "11.0.0.1", "feff::1", "2001:db8::1", "notlocalhost.com"] {
            XCTAssertFalse(WebFetcher.isPrivateHost(host), "\(host) must not be blocked")
        }
    }

    func testFetchRejectsPrivateHostWithoutNetwork() async {
        let fetcher = WebFetcher()
        await assertWebError(.blocked("private host")) {
            _ = try await fetcher.fetch(url: URL(string: "http://127.0.0.1/secret")!)
        }
        await assertWebError(.blocked("private host")) {
            _ = try await fetcher.fetch(url: URL(string: "http://localhost/admin")!)
        }
    }

    // MARK: Helpers

    private func assertWebError(_ expected: WebError,
                                file: StaticString = #filePath,
                                line: UInt = #line,
                                _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as WebError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
