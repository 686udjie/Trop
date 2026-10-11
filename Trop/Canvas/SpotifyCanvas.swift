//
//  SpotifyCanvas.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import Foundation

/// A looping clip that belongs behind a track's still artwork.
struct CanvasClip: Equatable {
    let url: URL
    let title: String
    let artist: String
    let album: String?
}

/// Endpoints, user agents and persisted-query hashes for the canvas route.
enum CanvasEndpoints {
    static let restSearch = "https://api.spotify.com/v1/search"
    static let canvazCache = "https://spclient.wg.spotify.com/canvaz-cache/v0/canvases"
    static let pathfinderSearch = "https://api-partner.spotify.com/pathfinder/v1/query"
    static let pathfinderCanvas = "https://api-partner.spotify.com/pathfinder/v2/query"

    /// The web player's own track-search query id.
    static let searchQueryHash = "bc1ca2fcd0ba1013a0fc88e6cc4f190af501851e3dafd3e1ef85840297694428"
    /// The `canvas` query's hash as of January 2026.
    static let knownCanvasHash = "575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f"

    /// Last known-good `profileAttributes` query hash, read live the same way
    /// as the canvas one. Asks for the listener's own profile the way the
    /// web player does (`data.me.profile`): `api.spotify.com/v1/me` stays
    /// quota-gated for these tokens, but the player never calls it either.
    static let knownProfileHash = "08ffb4730af3746e04a8301396f20875dbbce10c75243803091a9274eacc8ac0"

    static let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
    /// spclient gates the protobuf path to its own apps by UA; wear a mobile client's.
    static let appUserAgent = "Spotify/9.0.34.593 iOS/18.4 (iPhone15,3)"
}

/// Text normalization shared by searching and answer matching.
enum CanvasText {
    /// Lowercased, trimmed, punctuation-light form for equality checks.
    static func normalized(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\p{P}\\p{S}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Splits a multi-artist credit on common separators.
    static func splitArtists(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",&•·|"))
            .map { normalized($0) }
            .filter { !$0.isEmpty }
    }

    /// Strips the packaging YouTube titles carry that catalogues never see:
    /// "| Official Video", bracketed tags, "(lyrical)" and friends.
    static func cleanedTrack(_ s: String) -> String {
        var out = s
        if let pipe = out.range(of: " | ") { out = String(out[..<pipe.lowerBound]) }
        out = out.replacingOccurrences(
            of: "\\((?:from|official|lyrical|lyric|video|audio|music video)[^)]*\\)",
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        out = out.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(
            of: "\\b(?:official (?:video|audio|music video)|lyrical|lyric|full song|4k video|m\\/v)\\b",
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? s : out
    }
}

enum SpotifyCanvas {
    private struct TrackHit {
        let uri: String
        let title: String
        let artist: String
        let album: String?
    }

    /// The canvas for a track, or nil when there is none. Never throws.
    static func search(title: String, artist: String, album: String?) async -> CanvasClip? {
        guard let token = await CanvasSpotifyToken.shared.accessToken() else { return nil }
        var hit = await searchViaPathfinder(title: title, artist: artist, album: album, token: token)
        if hit == nil {
            hit = await searchViaRest(title: title, artist: artist, album: album, token: token)
        }
        guard let hit else { return nil }
        guard let url = await fetchCanvasUrl(trackUri: hit.uri, token: token) else { return nil }
        return CanvasClip(url: url, title: hit.title, artist: hit.artist, album: hit.album)
    }

    // MARK: - Track search

    private static func searchViaPathfinder(title: String, artist: String, album: String?, token: String) async -> TrackHit? {
        guard let clientToken = await CanvasSpotifyToken.shared.clientToken() else { return nil }
        let term = [title, artist, album].compactMap { $0 }.joined(separator: " ")
        let variables = """
            {"searchTerm":"\(jsonEscape(term))","offset":0,"limit":10,\
            "numberOfTopResults":5,"includeAudiobooks":false,"includePreReleases":false}
            """
        var components = URLComponents(string: CanvasEndpoints.pathfinderSearch)!
        components.queryItems = [
            URLQueryItem(name: "operationName", value: "searchTracks"),
            URLQueryItem(name: "variables", value: variables),
            URLQueryItem(name: "extensions", value: #"{"persistedQuery":{"version":1,"sha256Hash":"\#(CanvasEndpoints.searchQueryHash)"}}"#)
        ]
        guard let url = components.url else { return nil }
        let headers = [
            "Authorization": "Bearer \(token)", "Client-Token": clientToken,
            "App-platform": "WebPlayer", "Accept": "application/json",
            "User-Agent": CanvasEndpoints.webUserAgent
        ]
        guard let body = await get(url: url, headers: headers),
              let first = (body["data"] as? [String: Any])?["searchV2"] as? [String: Any]
        else { return nil }
        guard let tracks = (first["tracksV2"] as? [String: Any])?["items"] as? [[String: Any]],
              let firstItem = tracks.first,
              let item = (firstItem["item"] as? [String: Any])?["data"] as? [String: Any]
        else { return nil }
        let uri: String? = (item["uri"] as? String) ?? (item["id"] as? String).map { "spotify:track:\($0)" }
        guard let uri else { return nil }
        return TrackHit(uri: uri, title: title, artist: artist, album: album)
    }

    private static func searchViaRest(title: String, artist: String, album: String?, token: String) async -> TrackHit? {
        let term = [title, artist, album].compactMap { $0 }.joined(separator: " ")
        var components = URLComponents(string: CanvasEndpoints.restSearch)!
        components.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url,
              let body = await get(url: url, headers: await authHeaders(token: token)),
              let items = (body["tracks"] as? [String: Any])?["items"] as? [[String: Any]]
        else { return nil }
        for item in items {
            guard let trackTitle = item["name"] as? String,
                  let artists = (item["artists"] as? [[String: Any]])?.compactMap({ $0["name"] as? String }),
                  let uri = item["uri"] as? String,
                  isMatch(gotName: trackTitle, gotArtists: artists, wantName: title, wantArtist: artist)
            else { continue }
            let albumName = (item["album"] as? [String: Any])?["name"] as? String
            return TrackHit(uri: uri, title: trackTitle, artist: artists.joined(separator: ", "), album: albumName)
        }
        return nil
    }

    static func sessionCheck(token: String, clientToken: String?) async -> Bool {
        let variables = """
            {"searchTerm":"test","offset":0,"limit":1,\
            "numberOfTopResults":1,"includeAudiobooks":false,"includePreReleases":false}
            """
        var components = URLComponents(string: CanvasEndpoints.pathfinderSearch)!
        components.queryItems = [
            URLQueryItem(name: "operationName", value: "searchTracks"),
            URLQueryItem(name: "variables", value: variables),
            URLQueryItem(name: "extensions", value: #"{"persistedQuery":{"version":1,"sha256Hash":"\#(CanvasEndpoints.searchQueryHash)"}}"#)
        ]
        guard let url = components.url else { return false }
        var headers = [
            "Authorization": "Bearer \(token)",
            "App-platform": "WebPlayer", "Accept": "application/json",
            "User-Agent": CanvasEndpoints.webUserAgent
        ]
        if let clientToken { headers["Client-Token"] = clientToken }
        guard let body = await get(url: url, headers: headers) else { return false }
        return (body["data"] as? [String: Any])?["searchV2"] != nil
    }

    static func isMatch(gotName: String, gotArtists: [String], wantName: String, wantArtist: String) -> Bool {
        guard CanvasText.normalized(gotName) == CanvasText.normalized(wantName) else { return false }
        let wanted = CanvasText.splitArtists(wantArtist)
        let credited = gotArtists.map { CanvasText.normalized($0) }.filter { !$0.isEmpty }
        guard !wanted.isEmpty, !credited.isEmpty else { return false }
        return wanted.allSatisfy { want in credited.contains(want) }
    }

    // MARK: - Profile via Pathfinder

    static func fetchProfileViaPathfinder(token: String, clientToken: String?) async -> SpotifyProfile? {
        let hash = await CanvasQueryHashes.shared.hash(operation: "profileAttributes", fallback: CanvasEndpoints.knownProfileHash)
        for endpoint in [CanvasEndpoints.pathfinderSearch, CanvasEndpoints.pathfinderCanvas] {
            guard let body = await postProfileQuery(endpoint: endpoint, hash: hash, token: token, clientToken: clientToken),
                  let profile = parseProfile(body)
            else { continue }
            return profile
        }
        return nil
    }

    private static func postProfileQuery(endpoint: String, hash: String, token: String, clientToken: String?) async -> [String: Any]? {
        guard let url = URL(string: endpoint) else { return nil }
        let payload: [String: Any] = [
            "operationName": "profileAttributes",
            "variables": [String: Any](),
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": hash]]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let clientToken { request.setValue(clientToken, forHTTPHeaderField: "Client-Token") }
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func parseProfile(_ body: [String: Any]) -> SpotifyProfile? {
        guard let me = body["data"] as? [String: Any],
              let p = me["me"] as? [String: Any],
              let profile = p["profile"] as? [String: Any]
        else { return nil }
        let uri = profile["uri"] as? String ?? ""
        let username = profile["username"] as? String ?? ""
        let userId = uri.split(separator: ":").last.map(String.init) ?? username
        guard !userId.isEmpty else { return nil }
        let name = (profile["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = ((profile["avatar"] as? [String: Any])?["sources"] as? [[String: Any]]) ?? []
        let avatar = sources
            .compactMap({ s -> (URL, Int)? in
                guard let urlString = s["url"] as? String, let url = URL(string: urlString) else { return nil }
                return (url, (s["width"] as? NSNumber)?.intValue ?? 0)
            })
            .max { $0.1 < $1.1 }?.0
        return SpotifyProfile(
            userId: userId,
            displayName: (name?.isEmpty == false ? name! : username),
            avatarURL: avatar,
            product: nil
        )
    }

    // MARK: - Canvas fetch

    private static func fetchCanvasUrl(trackUri: String, token: String) async -> URL? {
        let hash = await CanvasQueryHashes.shared.hash(fallback: CanvasEndpoints.knownCanvasHash)
        let answer = parseCanvasAnswer(await postCanvasQuery(trackUri: trackUri, token: token, hash: hash))
        switch answer {
        case let .found(url):
            return url
        case .noCanvas:
            return await fetchViaCanvaz(trackUri: trackUri, token: token)
        case let .failed(staleHash):
            if staleHash {
                let freshHash = await CanvasQueryHashes.shared.hash(fallback: CanvasEndpoints.knownCanvasHash, forceRefresh: true)
                let retry = await postCanvasQuery(trackUri: trackUri, token: token, hash: freshHash)
                if case let .found(url) = parseCanvasAnswer(retry) { return url }
            }
            return await fetchViaCanvaz(trackUri: trackUri, token: token)
        }
    }

    private enum CanvasAnswer {
        case found(URL)
        case noCanvas
        case failed(staleHash: Bool)
    }

    private static func postCanvasQuery(trackUri: String, token: String, hash: String) async -> [String: Any]? {
        guard let url = URL(string: CanvasEndpoints.pathfinderCanvas) else { return nil }
        let payload: [String: Any] = [
            "operationName": "canvas",
            "variables": ["trackUri": trackUri],
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": hash]]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        for (name, value) in await authHeaders(token: token) { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func parseCanvasAnswer(_ body: [String: Any]?) -> CanvasAnswer {
        guard let body else { return .failed(staleHash: false) }
        guard let data = body["data"] as? [String: Any] else {
            let errors = (body["errors"] as? [[String: Any]])?.compactMap { $0["message"] as? String } ?? []
            let stale = errors.contains { $0.localizedCaseInsensitiveContains("PersistedQueryNotFound") }
            return .failed(staleHash: stale)
        }
        guard let canvas = (data["trackUnion"] as? [String: Any])?["canvas"] as? [String: Any] else {
            return .noCanvas
        }
        guard let urlString = canvas["url"] as? String, urlString.hasPrefix("https://"),
              urlString.range(of: #"\.mp4(?:[?#]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let url = URL(string: urlString)
        else { return .noCanvas }
        return .found(url)
    }

    // MARK: - canvaz-cache protobuf fallback

    /// `CanvasRequest { repeated Track tracks = 1; Track { string track_uri = 1; } }`
    private static func fetchViaCanvaz(trackUri: String, token: String) async -> URL? {
        let track = CanvasProtobuf.encode { $0.writeString(field: 1, value: trackUri) }
        let body = CanvasProtobuf.encode { $0.writeBytes(field: 1, value: track) }
        guard let url = URL(string: CanvasEndpoints.canvazCache) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("application/protobuf", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue(CanvasEndpoints.appUserAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in await authHeaders(token: token) { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        let hits = CanvasProtobuf.decodeCanvases(data)
        if let own = hits.first(where: { $0.trackUri == trackUri }) ?? hits.first, let url = own.url {
            return url
        }
        guard let text = String(data: data, encoding: .isoLatin1),
              let match = text.range(of: #"https://[^"'\s]+\.cnvs\.mp4"#, options: .regularExpression),
              let url = URL(string: String(text[match]))
        else { return nil }
        return url
    }

    // MARK: - HTTP helpers

    private static func authHeaders(token: String) async -> [String: String] {
        var headers = ["Authorization": "Bearer \(token)", "User-Agent": CanvasEndpoints.webUserAgent]
        if let client = await CanvasSpotifyToken.shared.clientToken() {
            headers["Client-Token"] = client
        }
        return headers
    }

    private static func get(url: URL, headers: [String: String]) async -> [String: Any]? {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Live query hash

actor CanvasQueryHashes {
    static let shared = CanvasQueryHashes()

    private static let foundTTL: TimeInterval = 12 * 3600
    private static let missedTTL: TimeInterval = 30 * 60
    private static let maxScripts = 8

    private var hashes: [String: String] = [:]
    private var checkedAt: [String: Date] = [:]

    func hash(operation: String = "canvas", fallback: String, forceRefresh: Bool = false) async -> String {
        let currentHash = hashes[operation]
        let age = Date().timeIntervalSince(checkedAt[operation] ?? .distantPast)
        let ttl = currentHash == nil ? Self.missedTTL : Self.foundTTL
        if !forceRefresh, age < ttl { return currentHash ?? fallback }
        checkedAt[operation] = Date()
        if let found = await lookUp(operation: operation) {
            hashes[operation] = found
            return found
        }
        return hashes[operation] ?? fallback
    }

    private func lookUp(operation: String) async -> String? {
        guard let html = await fetch("https://open.spotify.com/") else { return nil }
        for script in webPlayerScripts(html).prefix(Self.maxScripts) {
            guard let body = await fetch(script), let found = findHash(body, operation: operation) else { continue }
            return found
        }
        return nil
    }

    private func fetch(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    private func webPlayerScripts(_ html: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let pattern = #"https://open\.spotifycdn\.com/cdn/build/web-player/[A-Za-z0-9._~-]+\.js"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let url = String(html[Range(match.range, in: html)!])
            if seen.insert(url).inserted { out.append(url) }
        }
        return out
    }

    private func findHash(_ script: String, operation: String = "canvas") -> String? {
        let pattern = #"["'](\w+)["']\s*,\s*["']query["']\s*,\s*["']([0-9a-f]{64})["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: script, range: NSRange(script.startIndex..., in: script)) {
            guard let nameRange = Range(match.range(at: 1), in: script),
                  let hashRange = Range(match.range(at: 2), in: script),
                  String(script[nameRange]) == operation
            else { continue }
            return String(script[hashRange])
        }
        return nil
    }
}

// MARK: - Minimal protobuf codec

enum CanvasProtobuf {
    struct Writer {
        private(set) var data = Data()

        mutating func writeVarint(_ value: UInt64) {
            var v = value
            while v >= 0x80 {
                data.append(UInt8(v & 0x7F | 0x80))
                v >>= 7
            }
            data.append(UInt8(v))
        }

        mutating func writeTag(field: Int, wireType: Int) {
            writeVarint(UInt64(field << 3 | wireType))
        }

        mutating func writeString(field: Int, value: String) {
            writeBytes(field: field, value: Data(value.utf8))
        }

        mutating func writeBytes(field: Int, value: Data) {
            writeTag(field: field, wireType: 2)
            writeVarint(UInt64(value.count))
            data.append(value)
        }
    }

    static func encode(_ build: (inout Writer) -> Void) -> Data {
        var writer = Writer()
        build(&writer)
        return writer.data
    }

    struct CanvasHit {
        let id: String?
        let url: URL?
        let trackUri: String?
    }

    /// `CanvasResponse { repeated Canvas canvases = 1; }`,
    /// `Canvas { id = 1; canvas_url = 2; ...; track_uri = 5; ... }`.
    static func decodeCanvases(_ data: Data) -> [CanvasHit] {
        var hits: [CanvasHit] = []
        var reader = Reader(data: data)
        while !reader.isAtEnd {
            guard let tag = reader.readVarint(), tag != 0 else { break }
            if Int(tag >> 3) == 1, let bytes = reader.readBytes() {
                if let hit = decodeCanvas(bytes) { hits.append(hit) }
            } else {
                reader.skipField(tag: tag)
            }
        }
        return hits
    }

    private static func decodeCanvas(_ data: Data) -> CanvasHit? {
        var id: String?
        var url: URL?
        var trackUri: String?
        var reader = Reader(data: data)
        while !reader.isAtEnd {
            guard let tag = reader.readVarint(), tag != 0 else { break }
            switch Int(tag >> 3) {
            case 1: id = reader.readString()
            case 2: url = reader.readString().flatMap(URL.init(string:))
            case 5: trackUri = reader.readString()
            default: reader.skipField(tag: tag)
            }
        }
        guard let url else { return nil }
        return CanvasHit(id: id, url: url, trackUri: trackUri)
    }

    private struct Reader {
        let data: Data
        var offset = 0
        var isAtEnd: Bool { offset >= data.count }

        mutating func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift = 0
            while offset < data.count {
                let byte = data[offset]
                offset += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                guard shift < 64 else { return nil }
            }
            return nil
        }

        mutating func readBytes() -> Data? {
            guard let length = readVarint(), offset + Int(length) <= data.count else { return nil }
            let bytes = data[offset ..< offset + Int(length)]
            offset += Int(length)
            return Data(bytes)
        }

        mutating func readString() -> String? {
            readBytes().flatMap { String(data: $0, encoding: .utf8) }
        }

        mutating func skipField(tag: UInt64) {
            switch tag & 0x7 {
            case 0: _ = readVarint()
            case 1: offset += 8
            case 2: _ = readBytes()
            case 5: offset += 4
            default: offset = data.count
            }
            offset = min(offset, data.count)
        }
    }
}
