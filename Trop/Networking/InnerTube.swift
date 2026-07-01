//
//  InnerTube.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Singleton actor that handles all InnerTube API communication
actor InnerTube {
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let maxRetries = 3
    private let retryBaseDelay: Duration = .milliseconds(500)
    private let retryBackoffFactor = 2.0

    // Singleton — declared nonisolated so callers don't need `await self`
    nonisolated static let shared = InnerTube()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // Bundles the mutable session fields passed through internal helpers
    private struct Session {
        let cookies: [String: String]
        let sapisid: String?
        let visitorData: String?
    }

    // Actor-isolated mutable session state
    private var cookies: [String: String] = [:]
    private var sapisid: String?
    private var visitorData: String?

    // Loads persisted auth state into the session
    func loadState(from store: CookieStore) async {
        cookies = await store.cookies()
        sapisid = await store.sapisid()
        visitorData = await store.visitorData()
    }

    // Ensures visitorData is set, fetching it via browse if needed
    func ensureVisitorData() async throws {
        if visitorData != nil { return }
        _ = try await browse(browseId: "FEmusic_home")
    }

    // Fetches browse pages (home, library, artist, album, playlist)
    func browse(
        browseId: String? = nil,
        params: String? = nil,
        continuation: String? = nil,
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> [String: Any] {
        let ctx = buildContextDict(client: client, locale: locale)
        var body: [String: Any] = ["context": ctx]
        if let browseId = browseId { body["browseId"] = browseId }
        if let params = params { body["params"] = params }
        if let continuation = continuation { body["continuation"] = continuation }
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        let json = try await post(endpoint: "browse", body: body, client: client, session: session)
        if let rctx = json["responseContext"] as? [String: Any], let vd = rctx["visitorData"] as? String {
            visitorData = vd
            print("[InnerTube] Extracted visitorData from browse response")
        }
        return json
    }

    // Fetches stream URLs and metadata for a specific video
    func player(
        videoId: String,
        playlistId: String? = nil,
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default,
        signatureTimestamp: Int? = nil,
        poToken: String? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale),
            "videoId": videoId, "contentCheckOk": true, "racyCheckOk": true
        ]
        if let playlistId = playlistId { body["playlistId"] = playlistId }
        if let signatureTimestamp = signatureTimestamp {
            body["playbackContext"] = ["contentPlaybackContext": ["signatureTimestamp": signatureTimestamp]]
        }
        if let poToken = poToken {
            body["serviceIntegrityDimensions"] = ["poToken": poToken]
        }
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "player", body: body, client: client, session: session)
    }

    // Fetches player response and decodes into typed models
    func playerResponse(
        videoId: String,
        playlistId: String? = nil,
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default,
        signatureTimestamp: Int? = nil,
        poToken: String? = nil
    ) async throws -> PlayerResponse {
        var body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale),
            "videoId": videoId, "contentCheckOk": true, "racyCheckOk": true
        ]
        if let playlistId = playlistId { body["playlistId"] = playlistId }
        if let signatureTimestamp = signatureTimestamp {
            body["playbackContext"] = ["contentPlaybackContext": ["signatureTimestamp": signatureTimestamp]]
        }
        if let poToken = poToken {
            body["serviceIntegrityDimensions"] = ["poToken": poToken]
        }
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await postDecodable(endpoint: "player", body: body, client: client, session: session)
    }

    // Fetches queue data (playlist contents, related songs, radio)
    func next(
        videoId: String? = nil,
        playlistId: String? = nil,
        index: Int? = nil,
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale)
        ]
        if let videoId = videoId { body["videoId"] = videoId }
        if let playlistId = playlistId { body["playlistId"] = playlistId }
        if let index = index { body["index"] = index }
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "next", body: body, client: client, session: session)
    }

    // Searches YouTube Music
    func search(
        query: String,
        params: String? = nil,
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale),
            "query": query
        ]
        if let params = params { body["params"] = params }
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "search", body: body, client: client, session: session)
    }

    // Fetches account menu info — used to verify logged-in state
    func accountMenu(
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "account/account_menu", body: ["context": buildContextDict(client: client, locale: locale)], client: client, session: session)
    }

    // Fetches account info (name, email, profile picture)
    func accountInfo(
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> AccountInfo {
        let json = try await accountMenu(client: client, locale: locale)
        return extractAccountInfo(from: json)
    }

    private func extractRunsText(_ dict: [String: Any]?) -> String? {
        guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
        return first["text"] as? String
    }

    private func extractThumbnailUrl(_ dict: [String: Any]?) -> String? {
        guard let thumb = dict?["thumbnails"] as? [[String: Any]],
              let last = thumb.last,
              let url = last["url"] as? String else { return nil }
        return url
    }

    // Parses account menu response to extract AccountInfo
    private func extractAccountInfo(from json: [String: Any]) -> AccountInfo {
        guard let actions = json["actions"] as? [[String: Any]],
              let first = actions.first,
              let openPopup = first["openPopupAction"] as? [String: Any],
              let popup = openPopup["popup"] as? [String: Any],
              let multiPageMenu = popup["multiPageMenuRenderer"] as? [String: Any],
              let header = multiPageMenu["header"] as? [String: Any],
              let activeAccount = header["activeAccountHeaderRenderer"] as? [String: Any] else {
            return AccountInfo(name: "Guest")
        }
        let name = extractRunsText(activeAccount["accountName"] as? [String: Any]) ?? "Guest"
        let email = extractRunsText(activeAccount["email"] as? [String: Any])
        let handle = extractRunsText(activeAccount["channelHandle"] as? [String: Any])
        let photoUrl = extractThumbnailUrl(activeAccount["accountPhoto"] as? [String: Any])
        return AccountInfo(name: name, email: email, channelHandle: handle, thumbnailUrl: photoUrl)
    }

    // Core POST method — builds request, sends, parses JSON response
    private func post(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient,
        session: Session
    ) async throws -> [String: Any] {
        let (data, _) = try await withRetry(maxAttempts: maxRetries) {
            try await rawPost(endpoint: endpoint, body: body, client: client, session: session)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decodingFailed
        }
        return json
    }

    // Execute with retry: maxAttempts total tries with exponential backoff (500ms base, 2x factor)
    private func withRetry<T>(
        maxAttempts: Int = 3,
        backoffBase: Duration = .milliseconds(500),
        backoffFactor: Double = 2.0,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts - 1 else { break }
                let delay = backoffBase * pow(backoffFactor, Double(attempt))
                print("[InnerTube] Attempt \(attempt + 1)/\(maxAttempts) failed for \(error.localizedDescription). Retrying in \(delay)...")
                try? await Task.sleep(for: delay)
            }
        }
        throw lastError ?? InnerTubeError.httpError(statusCode: -1, data: Data())
    }

    // Core POST returning raw Data for typed decoding
    private func rawPost(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient,
        session: Session
    ) async throws -> (Data, HTTPURLResponse) {
        let request = RequestBuilder.buildRequest(
            endpoint: endpoint,
            body: body,
            client: client,
            visitorData: session.visitorData,
            cookies: session.cookies,
            sapisid: session.sapisid
        )
        let (data, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnerTubeError.invalidResponse
        }
        if !(200...299).contains(httpResponse.statusCode) {
            if let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                print("[InnerTube] ❌ Request body for \(endpoint) [\(client.clientName)]:\n\(bodyStr)")
            }
        print("[InnerTube] ❌ Request headers:")
        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers {
                print("[InnerTube] \(key): \(value)")
            }
        }
            if let bodyStr = String(data: data, encoding: .utf8) {
                print("[InnerTube] ❌ Response body:\n\(bodyStr)")
            }
            throw InnerTubeError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        return (data, httpResponse)
    }

    // POST endpoint and decode into a Decodable type
    private func postDecodable<T: Decodable>(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient,
        session: Session
    ) async throws -> T {
        let (data, _) = try await rawPost(endpoint: endpoint, body: body, client: client, session: session)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8) {
                let preview = raw.prefix(2000)
                print("[InnerTube] Decoding failed for \(endpoint) [\(client.clientName)]. Raw response:\n\(preview)")
            }
            throw error
        }
    }

    // Like or unlike a video
    func like(videoId: String, client: YouTubeClient = .webRemix, locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "like/like", body: ["context": buildContextDict(client: client, locale: locale), "target": ["videoId": videoId]], client: client, session: session)
    }

    func unlike(videoId: String, client: YouTubeClient = .webRemix, locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "like/removelike", body: ["context": buildContextDict(client: client, locale: locale), "target": ["videoId": videoId]], client: client, session: session)
    }

    // Send feedback tokens (library add/remove)
    func feedback(tokens: [String], client: YouTubeClient = .webRemix, locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "feedback", body: ["context": buildContextDict(client: client, locale: locale), "feedbackTokens": tokens], client: client, session: session)
    }

    // Edit a playlist (add, remove, or reorder videos)
    func editPlaylist(playlistId: String, actions: [[String: Any]],
                      client: YouTubeClient = .webRemix,
                      locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        let body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale),
            "playlistId": playlistId,
            "actions": actions
        ]
        return try await post(endpoint: "browse/edit_playlist", body: body, client: client, session: session)
    }

    // Create a new playlist
    func createPlaylist(title: String, description: String? = nil, client: YouTubeClient = .webRemix, locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        var body: [String: Any] = ["context": buildContextDict(client: client, locale: locale), "title": title]
        if let description { body["description"] = description }
        return try await post(endpoint: "playlist/create", body: body, client: client, session: session)
    }

    // Delete a playlist
    func deletePlaylist(playlistId: String, client: YouTubeClient = .webRemix, locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "playlist/delete", body: ["context": buildContextDict(client: client, locale: locale), "playlistId": playlistId], client: client, session: session)
    }

    // Get search suggestions (autocomplete)
    func searchSuggestions(input: String, client: YouTubeClient = .webRemix, locale: YouTubeLocale = .default) async throws -> [String: Any] {
        let session = Session(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
        return try await post(endpoint: "music/get_search_suggestions", body: ["context": buildContextDict(client: client, locale: locale), "input": input], client: client, session: session)
    }

    // Builds the inner context dictionary sent with every API request
    private func buildContextDict(
        client: YouTubeClient,
        locale: YouTubeLocale,
        visitorData: String? = nil
    ) -> [String: Any] {
        var clientDict: [String: Any] = [
            "clientName": client.clientName,
            "clientVersion": client.clientVersion,
            "gl": locale.gl,
            "hl": locale.hl
        ]
        if let visitorData = visitorData {
            clientDict["visitorData"] = visitorData
        }
        if let osName = client.osName { clientDict["osName"] = osName }
        if let osVersion = client.osVersion { clientDict["osVersion"] = osVersion }
        if let deviceMake = client.deviceMake { clientDict["deviceMake"] = deviceMake }
        if let deviceModel = client.deviceModel { clientDict["deviceModel"] = deviceModel }
        if let androidSdkVersion = client.androidSdkVersion { clientDict["androidSdkVersion"] = androidSdkVersion }
        return [
            "client": clientDict,
            "request": ["internalExperimentFlags": [] as [String], "useSsl": true],
            "user": ["lockedSafetyMode": false]
        ]
    }
}

// Error types returned by InnerTube API calls
enum InnerTubeError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let statusCode, let data):
            let body = String(data: data, encoding: .utf8) ?? "empty"
            return "HTTP \(statusCode): \(body)"
        case .decodingFailed: return "Failed to decode response JSON"
        }
    }
}
