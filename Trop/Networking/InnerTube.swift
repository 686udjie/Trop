//
//  InnerTube.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Singleton actor that handles all InnerTube API communication
actor InnerTube {
    static let shared = InnerTube()

    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // Session state
    private var visitorData: String?
    private var cookies: [String: String] = [:]
    private var sapisid: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Snake-case keys match YouTube's JSON convention
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // Loads persisted auth state into the session
    func loadState(from store: CookieStore) {
        cookies = store.cookies
        sapisid = store.sapisid
        visitorData = store.visitorData
    }

    // Ensures visitorData is set, fetching it via browse if needed
    func ensureVisitorData() async throws {
        if visitorData != nil { return }
        _ = try await browse(browseId: "FEmusic_home")
    }

    // Fetches browse pages (home, library, artist, album, playlist)
    func browse(
        browseId: String,
        params: String? = nil,
        continuation: String? = nil,
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale)
        ]
        body["browseId"] = browseId
        if let params = params {
            body["params"] = params
        }
        if let continuation = continuation {
            body["continuation"] = continuation
        }
        let json = try await post(endpoint: "browse", body: body, client: client)
        // Extract and persist visitorData from browse response
        if let ctx = json["responseContext"] as? [String: Any],
           let vd = ctx["visitorData"] as? String {
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
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        if let playlistId = playlistId {
            body["playlistId"] = playlistId
        }
        if let signatureTimestamp = signatureTimestamp {
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "signatureTimestamp": signatureTimestamp
                ]
            ]
        }
        if let poToken = poToken {
            body["serviceIntegrityDimensions"] = [
                "poToken": poToken
            ]
        }
        return try await post(endpoint: "player", body: body, client: client)
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
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        if let playlistId = playlistId {
            body["playlistId"] = playlistId
        }
        if let signatureTimestamp = signatureTimestamp {
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "signatureTimestamp": signatureTimestamp
                ]
            ]
        }
        if let poToken = poToken {
            body["serviceIntegrityDimensions"] = [
                "poToken": poToken
            ]
        }
        return try await postDecodable(endpoint: "player", body: body, client: client)
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
        if let videoId = videoId {
            body["videoId"] = videoId
        }
        if let playlistId = playlistId {
            body["playlistId"] = playlistId
        }
        if let index = index {
            body["index"] = index
        }
        return try await post(endpoint: "next", body: body, client: client)
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
        if let params = params {
            body["params"] = params
        }
        return try await post(endpoint: "search", body: body, client: client)
    }

    // Fetches account menu info — used to verify logged-in state
    func accountMenu(
        client: YouTubeClient = .webRemix,
        locale: YouTubeLocale = .default
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": buildContextDict(client: client, locale: locale)
        ]
        return try await post(endpoint: "account/account_menu", body: body, client: client)
    }

    // Core POST method — builds request, sends, parses JSON response
    private func post(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient
    ) async throws -> [String: Any] {
        let (data, _) = try await rawPost(endpoint: endpoint, body: body, client: client)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decodingFailed
        }

        return json
    }

    // Core POST returning raw Data for typed decoding
    private func rawPost(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient
    ) async throws -> (Data, HTTPURLResponse) {
        let request = RequestBuilder.buildRequest(
            endpoint: endpoint,
            body: body,
            client: client,
            visitorData: visitorData,
            cookies: cookies,
            sapisid: sapisid
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnerTubeError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                print("[InnerTube] ❌ Request body for \(endpoint) [\(client.clientName)]:\n\(bodyStr)")
            }
            print("[InnerTube] ❌ Request headers:")
            for (key, value) in request.allHTTPHeaderFields ?? [:] {
                print("[InnerTube]   \(key): \(value)")
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
        client: YouTubeClient
    ) async throws -> T {
        let (data, _) = try await rawPost(endpoint: endpoint, body: body, client: client)
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

    // Builds the inner context dictionary sent with every API request
    private func buildContextDict(
        client: YouTubeClient,
        locale: YouTubeLocale
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
        if let osName = client.osName {
            clientDict["osName"] = osName
        }
        if let osVersion = client.osVersion {
            clientDict["osVersion"] = osVersion
        }
        if let deviceMake = client.deviceMake {
            clientDict["deviceMake"] = deviceMake
        }
        if let deviceModel = client.deviceModel {
            clientDict["deviceModel"] = deviceModel
        }
        if let androidSdkVersion = client.androidSdkVersion {
            clientDict["androidSdkVersion"] = androidSdkVersion
        }

        let context: [String: Any] = [
            "client": clientDict,
            "request": [
                "internalExperimentFlags": [] as [String],
                "useSsl": true
            ],
            "user": [
                "lockedSafetyMode": false
            ]
        ]

        return context
    }

}

// Error types returned by InnerTube API calls
enum InnerTubeError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let data):
            let body = String(data: data, encoding: .utf8) ?? "empty"
            return "HTTP \(statusCode): \(body)"
        case .decodingFailed:
            return "Failed to decode response JSON"
        }
    }
}
