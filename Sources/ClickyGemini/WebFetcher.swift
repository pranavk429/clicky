import Darwin
import Foundation

// MARK: - Public types

/// Result of fetching one web page. `text` is a readable, whitespace-collapsed
/// extraction truncated to the requested budget; `url` is the location actually
/// fetched after http/https redirects.
public struct WebFetchResult: Sendable {
    public let title: String?
    public let text: String
    public let url: URL

    public init(title: String?, text: String, url: URL) {
        self.title = title
        self.text = text
        self.url = url
    }
}

/// One web-search hit.
public struct WebSearchResult: Sendable {
    public let title: String
    public let url: URL
    public let snippet: String

    public init(title: String, url: URL, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// Web-access failures. `blocked` and `transport` carry short, non-content
/// details only — page content is never echoed into errors or logs.
public enum WebError: Error, Equatable {
    case invalidURL
    case blocked(String)
    case transport(String)
    case empty
}

// MARK: - Content classification

/// How `fetch` interprets a response body.
enum ContentKind: Equatable {
    case html
    case feed
    case plain
}

// MARK: - Redirect gate

/// Per-task redirect policy: http/https redirects are followed; anything else
/// is refused and recorded so the caller can fail closed with `.blocked`.
/// URLSession invokes the delegate off the calling thread, hence the lock.
final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var blocked: URL?

    var blockedURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            completionHandler(request)
        } else {
            lock.lock()
            blocked = request.url
            lock.unlock()
            completionHandler(nil)
        }
    }
}

// MARK: - WebFetcher

/// Read-only web access for the voice agent: fetch one page as text, or run a
/// keyless DuckDuckGo search. Foundation only; no cookies, credentials, cache,
/// or disk writes. http/https only, and redirects that leave those schemes fail
/// closed. Downloads are streamed and capped; page content is never logged.
public final class WebFetcher: @unchecked Sendable {

    /// Desktop User-Agent — some origins reject requests without one.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let requestTimeout: TimeInterval = 10
    static let maxDownloadBytes = 512 * 1024
    static let maxFeedItems = 30

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "en-US,en;q=0.9",
        ]
        self.session = URLSession(configuration: configuration)
    }

    // MARK: Public API

    /// Fetches `url` and returns a readable extraction: HTML becomes plain text,
    /// RSS/Atom feeds become one line per item, and `text/plain` passes through.
    public func fetch(url: URL, maxCharacters: Int = 4000) async throws -> WebFetchResult {
        let payload = try await collect(
            url: url,
            accept: "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5"
        )
        guard !payload.data.isEmpty else { throw WebError.empty }
        let raw = Self.decodeText(payload.data, encodingName: payload.encodingName)
        let source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw WebError.empty }

        switch Self.contentKind(mimeType: payload.mimeType, body: source) {
        case .plain:
            return WebFetchResult(title: nil,
                                  text: Self.truncate(source, maxCharacters: maxCharacters),
                                  url: payload.finalURL)
        case .feed:
            let feed = Self.rssToLines(source, limit: Self.maxFeedItems)
            let body: String
            if feed.lines.isEmpty {
                guard let feedTitle = feed.title, !feedTitle.isEmpty else { throw WebError.empty }
                body = feedTitle
            } else {
                body = feed.lines.joined(separator: "\n")
            }
            return WebFetchResult(title: feed.title,
                                  text: Self.truncate(body, maxCharacters: maxCharacters),
                                  url: payload.finalURL)
        case .html:
            let page = Self.htmlToText(source, maxCharacters: maxCharacters)
            guard !page.text.isEmpty else { throw WebError.empty }
            return WebFetchResult(title: page.title, text: page.text, url: payload.finalURL)
        }
    }

    /// Runs a keyless search via DuckDuckGo Lite and parses the result table.
    /// Zero parsed results throw `.empty` (fail soft; never crashes).
    public func search(query: String, maxResults: Int = 5) async throws -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, maxResults > 0 else { throw WebError.invalidURL }

        var components = URLComponents(string: "https://lite.duckduckgo.com/lite/")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components?.url else { throw WebError.invalidURL }

        let payload = try await collect(url: url,
                                        accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5")
        guard !payload.data.isEmpty else { throw WebError.empty }
        let html = Self.decodeText(payload.data, encodingName: payload.encodingName)
        let results = Self.parseDuckDuckGo(html, maxResults: maxResults)
        guard !results.isEmpty else { throw WebError.empty }
        return results
    }

    // MARK: Network layer

    private struct Payload {
        let data: Data
        let mimeType: String?
        let encodingName: String?
        let finalURL: URL
    }

    /// Validates the scheme, streams the body up to the download cap, and maps
    /// every failure to a `WebError`. The response body is never logged.
    private func collect(url: URL, accept: String) async throws -> Payload {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            throw WebError.invalidURL
        }
        guard !Self.isPrivateHost(host) else {
            throw WebError.blocked("private host")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue(accept, forHTTPHeaderField: "Accept")

        let policy = RedirectPolicy()
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: policy)
            guard let http = response as? HTTPURLResponse else {
                throw WebError.transport("non-HTTP response")
            }
            if policy.blockedURL != nil {
                throw WebError.blocked("redirect left http/https")
            }
            guard (200...299).contains(http.statusCode) else {
                throw WebError.transport("HTTP \(http.statusCode)")
            }

            var data = Data()
            data.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                data.append(byte)
                if data.count >= Self.maxDownloadBytes { break }
            }

            return Payload(data: data,
                           mimeType: http.mimeType,
                           encodingName: http.textEncodingName,
                           finalURL: http.url ?? url)
        } catch let error as WebError {
            throw error
        } catch {
            if policy.blockedURL != nil {
                throw WebError.blocked("redirect left http/https")
            }
            throw WebError.transport(Self.describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "URLError \(urlError.code.rawValue): \(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }

    static func decodeText(_ data: Data, encodingName: String?) -> String {
        if let encodingName, let encoding = stringEncoding(forIANAName: encodingName),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func stringEncoding(forIANAName name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}

// MARK: - Pure parsers (internal static; unit-testable without network)

extension WebFetcher {

    // MARK: HTML

    /// Extracts a title (first `<title>`) and single-line readable text from an
    /// HTML document.
    static func htmlToText(_ html: String, maxCharacters: Int = 4000) -> (title: String?, text: String) {
        var working = regexReplace(html, pattern: htmlCommentPattern, with: " ")
        working = removingElement(named: "script", from: working)
        working = removingElement(named: "style", from: working)
        working = removingElement(named: "noscript", from: working)

        var title: String?
        if let rawTitle = firstGroup(in: working, pattern: htmlTitlePattern) {
            let cleaned = cleanMarkup(rawTitle)
            if !cleaned.isEmpty { title = cleaned }
        }

        return (title, truncate(cleanMarkup(working), maxCharacters: maxCharacters))
    }

    /// Strips a whole element, including an unterminated trailing block (a
    /// capped download can cut a document mid-`<script>`).
    static func removingElement(named name: String, from html: String) -> String {
        var text = regexReplace(html,
                                pattern: #"(?is)<\#(name)\b[^>]*>.*?</\#(name)\s*>"#,
                                with: " ")
        text = regexReplace(text,
                            pattern: #"(?is)<\#(name)\b[^>]*>.*"#,
                            with: " ")
        return text
    }

    // MARK: Feeds

    /// Turns RSS/Atom XML into a feed title plus one readable line per item.
    static func rssToLines(_ xml: String, limit: Int = 30) -> (title: String?, lines: [String]) {
        let feedTitle = firstText(of: "title", in: xml)

        var lines: [String] = []
        let items = allFirstGroups(in: xml, pattern: feedItemPattern)
        for block in items {
            if lines.count >= limit { break }
            let itemTitle = firstText(of: "title", in: block)
            let summary = firstText(of: "description", in: block)
                ?? firstText(of: "summary", in: block)
                ?? firstText(of: "content", in: block)
            var line = itemTitle ?? ""
            if let summary, summary != itemTitle {
                line = line.isEmpty ? summary : "\(line) — \(summary)"
            }
            if !line.isEmpty { lines.append(line) }
        }

        if lines.isEmpty {
            lines = allFirstGroups(in: xml, pattern: feedLooseElementsPattern)
                .map(cleanFeedFragment)
                .filter { !$0.isEmpty }
            if lines.count > limit { lines = Array(lines.prefix(limit)) }
        }

        return (feedTitle, lines)
    }

    static func firstText(of element: String, in block: String) -> String? {
        guard let raw = firstGroup(in: block,
                                   pattern: #"(?is)<\#(element)\b[^>]*>(.*?)</\#(element)\s*>"#) else {
            return nil
        }
        let cleaned = cleanFeedFragment(raw)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func cleanFeedFragment(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<![CDATA[") {
            text.removeFirst("<![CDATA[".count)
            if text.hasSuffix("]]>") { text.removeLast(3) }
        }
        return cleanMarkup(text)
    }

    // MARK: Search

    /// Parses DuckDuckGo Lite's HTML result table. Falls back to external
    /// anchors if the result-specific markup ever drifts; returns `[]` when
    /// nothing usable is found (the caller maps that to `.empty`).
    static func parseDuckDuckGo(_ html: String, maxResults: Int = 5) -> [WebSearchResult] {
        guard maxResults > 0 else { return [] }
        var results: [WebSearchResult] = []

        let anchors = allCaptureGroups(in: html, pattern: ddgResultAnchorPattern)
        let snippets = allFirstGroups(in: html, pattern: ddgSnippetPattern).map(cleanMarkup)

        for (index, groups) in anchors.enumerated() {
            if results.count >= maxResults { break }
            guard groups.count >= 2,
                  let href = firstGroup(in: groups[0], pattern: hrefAttributePattern),
                  let url = searchResultURL(fromHref: href) else { continue }
            let title = cleanMarkup(groups[1])
            results.append(WebSearchResult(title: title.isEmpty ? (url.host ?? href) : title,
                                           url: url,
                                           snippet: index < snippets.count ? snippets[index] : ""))
        }

        if results.isEmpty {
            for groups in allCaptureGroups(in: html, pattern: ddgFallbackAnchorPattern) {
                if results.count >= maxResults { break }
                guard groups.count >= 2,
                      let url = URL(string: decodeEntities(groups[0])),
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                      let host = url.host?.lowercased(), !host.hasSuffix("duckduckgo.com") else { continue }
                let title = cleanMarkup(groups[1])
                guard title.count > 2 else { continue }
                results.append(WebSearchResult(title: title, url: url, snippet: ""))
            }
        }

        return results
    }

    /// Resolves a result-table href, unwrapping the `duckduckgo.com/l/?uddg=…`
    /// redirect when present. Anything that is not http(s) resolves to `nil`.
    static func searchResultURL(fromHref rawHref: String) -> URL? {
        let href = decodeEntities(rawHref).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return nil }

        let base = URL(string: "https://lite.duckduckgo.com")
        let candidate: URL?
        if href.hasPrefix("//") {
            candidate = URL(string: "https:" + href)
        } else if href.hasPrefix("/") {
            candidate = URL(string: href, relativeTo: base)?.absoluteURL
        } else {
            candidate = URL(string: href)
        }
        guard let url = candidate else { return nil }

        if let host = url.host?.lowercased(), host.hasSuffix("duckduckgo.com"),
           url.path == "/l" || url.path.hasPrefix("/l/"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let unwrapped = URL(string: target),
           let scheme = unwrapped.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return unwrapped
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    // MARK: Shared text helpers

    /// Strips tags, decodes entities, and collapses every whitespace run to a
    /// single space, yielding one readable line.
    static func cleanMarkup(_ source: String) -> String {
        var text = regexReplace(source, pattern: htmlBlockTagPattern, with: " ")
        text = regexReplace(text, pattern: htmlTagPattern, with: "")
        text = decodeEntities(text)
        return collapseWhitespace(text)
    }

    /// Decodes HTML entities in a single left-to-right pass, so `&amp;lt;`
    /// becomes the literal `&lt;` instead of cascading to `<`.
    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        guard let regex = try? NSRegularExpression(pattern: entityPattern) else { return input }
        let ns = input as NSString
        let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var output = ""
        output.reserveCapacity(input.count)
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let token = ns.substring(with: match.range)
            output += decodedEntity(token) ?? token
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            output += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return output
    }

    static func decodedEntity(_ token: String) -> String? {
        guard token.hasPrefix("&"), token.hasSuffix(";"), token.count > 2 else { return nil }
        let body = token.dropFirst().dropLast()
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let scalarValue = value, let scalar = Unicode.Scalar(scalarValue) else { return nil }
            return String(scalar)
        }
        return namedEntities[String(body)]
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func truncate(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        return String(text.prefix(maxCharacters))
    }

    static func contentKind(mimeType: String?, body: String) -> ContentKind {
        let type = (mimeType ?? "")
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if type == "text/plain" { return .plain }
        if type == "application/xhtml+xml" { return .html }
        if ["application/xml", "text/xml", "application/rss+xml", "application/atom+xml"].contains(type) {
            return .feed
        }
        if type.hasSuffix("+xml") { return .feed }
        if type.isEmpty { return body.hasPrefix("<?xml") ? .feed : .html }
        return .html
    }

    // MARK: Host validation

    /// Rejects hosts that point at the user's own machine or private network:
    /// "localhost", the ".local" (mDNS) suffix, and literal IPs in loopback /
    /// RFC-1918 / link-local ranges. Literal checks only — no DNS resolution —
    /// so a public-looking hostname that resolves to a private address is out of
    /// scope; this closes the obvious SSRF surface without pretending to be a
    /// complete network policy. IPv4-mapped IPv6 literals (`::ffff:a.b.c.d`) are
    /// unwrapped and checked with the same IPv4 rules.
    static func isPrivateHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())   // Foundation usually strips brackets already
        }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return isPrivateIPv4(withUnsafeBytes(of: ipv4) { Array($0.prefix(4)) })
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0.prefix(16)) }
            if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true }            // ::1
            if bytes[0] == 0xfe, (bytes[1] & 0xc0) == 0x80 { return true }                       // fe80::/10
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {     // ::ffff:a.b.c.d
                return isPrivateIPv4(Array(bytes[12..<16]))
            }
        }
        return false
    }

    private static func isPrivateIPv4(_ octets: [UInt8]) -> Bool {
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    // MARK: Regex helpers

    static func regexReplace(_ input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input,
                                              options: [],
                                              range: range,
                                              withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    static func firstGroup(in input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: input) else { return nil }
        return String(input[groupRange])
    }

    static func allFirstGroups(in input: String, pattern: String) -> [String] {
        allCaptureGroups(in: input, pattern: pattern).compactMap { $0.first }
    }

    /// Capture groups 1...n of every match. All groups in the patterns above
    /// are mandatory, so non-participating groups never occur here.
    static func allCaptureGroups(in input: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, options: [], range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: input).map { String(input[$0]) }
            }
        }
    }
}

// MARK: - Extraction patterns

private let htmlCommentPattern = #"(?is)<!--.*?-->"#
private let htmlTitlePattern = #"(?is)<title\b[^>]*>(.*?)</title\s*>"#
private let htmlBlockTagPattern = #"(?i)</?(?:br|p|div|li|tr|td|th|h[1-6]|section|article|blockquote|table|thead|tbody|ul|ol|dl|dt|dd|pre|figure|figcaption|header|footer|nav|main|aside|form|address|hr|details|summary)\b[^>]*>"#
private let htmlTagPattern = #"(?i)<[!/?]?[A-Za-z][^>]*>"#
private let entityPattern = #"&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});"#
private let feedItemPattern = #"(?is)<(?:item|entry)\b[^>]*>(.*?)</(?:item|entry)\s*>"#
private let feedLooseElementsPattern = #"(?is)<(?:description|summary)\b[^>]*>(.*?)</(?:description|summary)\s*>"#
private let ddgResultAnchorPattern = #"(?is)(<a\b[^>]*class\s*=\s*["'][^"']*result-link[^"']*["'][^>]*>)(.*?)</a\s*>"#
private let ddgSnippetPattern = #"(?is)<td\b[^>]*class\s*=\s*["'][^"']*result-snippet[^"']*["'][^>]*>(.*?)</td\s*>"#
private let ddgFallbackAnchorPattern = #"(?is)<a\b[^>]*href\s*=\s*["'](https?://[^"'\s]+)["'][^>]*>(.*?)</a\s*>"#
private let hrefAttributePattern = #"(?i)href\s*=\s*["']([^"']*)["']"#

/// Common named HTML entities. `&amp;` is decoded in the same single pass as
/// everything else, so chains like `&amp;lt;` never double-decode.
private let namedEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
    "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ", "shy": "",
    "mdash": "—", "ndash": "–", "minus": "−", "hellip": "…",
    "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    "sbquo": "‚", "bdquo": "„", "laquo": "«", "raquo": "»",
    "copy": "©", "reg": "®", "trade": "™", "deg": "°", "middot": "·",
    "bull": "•", "sect": "§", "para": "¶", "dagger": "†", "prime": "′",
    "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
    "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "half": "½",
    "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³", "micro": "µ",
    "permil": "‰", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔",
]
