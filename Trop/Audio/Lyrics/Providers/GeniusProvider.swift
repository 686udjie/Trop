//
//  GeniusProvider.swift
//  Trop
//
//  Created by 686udjie on 17/07/2026.
//

// https://github.com/spicetify/cli/blob/main/CustomApps/lyrics-plus/ProviderGenius.js

import Foundation

struct GeniusProvider: LyricsProvider {
    let id = "genius"
    let name = "Genius"

    private let searchBase = "https://genius.com/api/search/song"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        for title in titleVariants(query.title) {
            if let lines = try? await fetchOnce(artist: query.artist, title: title), !lines.isEmpty {
                return lines
            }
        }
        throw LyricsError.notFound
    }

    // MARK: - Search + scrape

    private func fetchOnce(artist: String, title: String) async throws -> [LyricLine] {
        let url = try searchURL(artist: artist, title: title)
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LyricsError.notFound
        }

        let decoded = try JSONDecoder().decode(GeniusSearchResponse.self, from: data)
        let hits = decoded.response.sections
            .compactMap { $0.hits }
            .flatMap { $0 }
        guard let first = hits.first else {
            throw LyricsError.notFound
        }

        return try await fetchLyricsPage(urlString: first.result.url)
    }

    private func fetchLyricsPage(urlString: String) async throws -> [LyricLine] {
        guard let url = URL(string: urlString) else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LyricsError.notFound
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw LyricsError.decodingFailed
        }

        let containers = extractLyricsContainers(html)
        guard !containers.isEmpty else {
            throw LyricsError.notFound
        }

        let combined = containers.joined(separator: "<br>")
        let text = htmlToText(combined)

        let lines = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(text: $0, startTime: nil) }

        guard !lines.isEmpty else { throw LyricsError.notFound }
        return lines
    }

    // MARK: - URL building

    private func searchURL(artist: String, title: String) throws -> URL {
        guard var components = URLComponents(string: searchBase) else { throw LyricsError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "q", value: "\(artist) \(title)")
        ]
        guard let url = components.url else { throw LyricsError.invalidURL }
        return url
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }

    // MARK: - Title variants

    private func titleVariants(_ title: String) -> [String] {
        var variants: [String] = []
        func add(_ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty, !variants.contains(v) { variants.append(v) }
        }

        add(title)
        // Strip parenthetical / bracketed extra info: (feat. X), [Remastered], etc.
        add(stripBrackets(title))
        // Strip trailing "feat./ft./featuring" clauses
        add(title.replacingOccurrences(of: #"(?i)\s*(feat\.?|ft\.?|featuring).*$"#, with: "", options: .regularExpression))
        return variants
    }

    private func stripBrackets(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\(.*?)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
    }

    // MARK: - HTML extraction

    private func extractLyricsContainers(_ html: String) -> [String] {
        var results: [String] = []
        let marker = "data-lyrics-container=\"true\""
        var scan = html.startIndex

        while let markerRange = html.range(of: marker, range: scan..<html.endIndex) {
            // Find the closing '>' of the opening tag
            let afterMarker = html[markerRange.upperBound...]
            guard let tagClose = afterMarker.firstIndex(of: ">") else { break }
            var pos = html.index(after: tagClose)
            var depth = 1
            let innerStart = pos

            while pos < html.endIndex, depth > 0 {
                let rest = html[pos...]
                if rest.hasPrefix("<div") {
                    depth += 1
                    if let gt = rest.firstIndex(of: ">") { pos = html.index(after: gt) } else { break }
                } else if rest.hasPrefix("</div>") {
                    depth -= 1
                    pos = html.index(pos, offsetBy: 6)
                    if depth == 0 {
                        let inner = String(html[innerStart..<html.index(before: pos)])
                        results.append(inner)
                    }
                } else {
                    pos = html.index(after: pos)
                }
            }

            scan = pos
        }
        return results
    }

    /// Convert a fragment of Genius lyrics HTML into plain text.
    private func htmlToText(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"</p>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .decodeHTMLEntities()
    }

    private func replaceNumericEntities(in string: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length))
        var result = string
        for match in matches.reversed() {
            guard let codeRange = Range(match.range(at: 1), in: string),
                  let code = UInt32(string[codeRange], radix: radix),
                  let scalar = UnicodeScalar(code) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
        }
        return result
    }
}

// MARK: - String extension

extension String {
    /// Decodes common HTML entities (named + numeric/hex) into their characters.
    fileprivate func decodeHTMLEntities() -> String {
        var result = self
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " "
        ]
        for (entity, char) in named {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        result = replaceNumericEntities(in: result, pattern: #"&#(\d+);"#, radix: 10)
        result = replaceNumericEntities(in: result, pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        return result
    }

    private func replaceNumericEntities(in string: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length))
        var result = string
        for match in matches.reversed() {
            guard let codeRange = Range(match.range(at: 1), in: string),
                  let code = UInt32(string[codeRange], radix: radix),
                  let scalar = UnicodeScalar(code) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
        }
        return result
    }
}

// MARK: - Search response models

private struct GeniusSearchResponse: Decodable {
    let response: Response

    struct Response: Decodable {
        let sections: [Section]
    }

    struct Section: Decodable {
        let hits: [Hit]?
    }

    struct Hit: Decodable {
        let result: Result
    }

    struct Result: Decodable {
        let url: String
        let fullTitle: String

        enum CodingKeys: String, CodingKey {
            case url
            case fullTitle = "full_title"
        }
    }
}
