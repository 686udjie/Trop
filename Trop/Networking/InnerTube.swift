//
//  InnerTube.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation
import CommonCrypto

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
        // Configure URLSession with standard InnerTube headers
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "X-Goog-Api-Format-Version": "1",
            "X-Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/"
        ]
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

    // Stores auth cookies from the login WebView
    func setCookies(_ cookies: [String: String]) {
        self.cookies = cookies
    }

    // Sets the visitor ID used across all requests
    func setVisitorData(_ data: String) {
        self.visitorData = data
    }

    // Sets the SAPISID cookie value for signed-in auth headers
    func setSAPISID(_ sapisid: String) {
        self.sapisid = sapisid
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
        return try await post(endpoint: "browse", body: body, client: client)
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

    // Core POST method — builds request, sends, parses JSON response
    private func post(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient
    ) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("\(client.clientId)", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")

        if let visitorData = visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        if !cookies.isEmpty {
            let cookieString = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }

        if let sapisid = sapisid {
            let timestamp = Int(Date().timeIntervalSince1970)
            let hash = sha1("\(timestamp) \(sapisid) https://music.youtube.com")
            request.setValue("SAPISIDHASH \(timestamp)_\(hash)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Send request and await response
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnerTubeError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw InnerTubeError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decodingFailed
        }

        return json
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

        let context: [String: Any] = [
            "client": clientDict,
            "request": ["useSsl": true]
        ]

        return context
    }

    // SHA1 hash used for SAPISID authorization header generation
    private func sha1(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
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
