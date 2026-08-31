//
//  LastFMService.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import CryptoKit

struct LastFMSession: Codable {
    let name: String
    let key: String
    let subscriber: Int
}

struct LastFMAuthResponse: Codable {
    let session: LastFMSession
}

struct LastFMTokenResponse: Codable {
    let token: String
}

struct LastFMErrorResponse: Codable {
    let error: Int
    let message: String
}

enum LastFMError: Error, LocalizedError {
    case notConfigured
    case network(Error)
    case http(Int, String)
    case api(Int, String)
    case missingSession
    case unauthorizedToken
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Last.fm API keys not configured"
        case .network(let e): return e.localizedDescription
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .api(let code, let msg): return "Last.fm error \(code): \(msg)"
        case .missingSession: return "Missing session key"
        case .unauthorizedToken: return "Token not yet authorized — please approve on Last.fm and tap Done"
        case .invalidResponse: return "Invalid response"
        }
    }
}

/// Handles signing and network calls to Last.fm.
final class LastFMService: @unchecked Sendable {
    static let shared = LastFMService()
    private init() {}

    var sessionKey: String? {
        get { LastFMTokenStore.shared.retrieveSessionKey() }
        set {
            if let v = newValue, !v.isEmpty {
                // keep username as-is
                let username = LastFMTokenStore.shared.retrieveUsername() ?? ""
                LastFMTokenStore.shared.store(sessionKey: v, username: username)
            }
        }
    }

    func configure(apiKey: String, secret: String) {
        LastFMDefaults.configure(apiKey: apiKey, secret: secret)
    }

    // MARK: - Signature

    private func apiSig(params: [String: String], secret: String) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        let concatenated = sorted.map { $0.key + $0.value }.joined() + secret
        let digest = Insecure.MD5.hash(data: Data(concatenated.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func formBody(params: [String: String], secret: String) -> Data? {
        var all = params
        let sig = apiSig(params: all, secret: secret)
        all["api_sig"] = sig
        all["format"] = "json"
        var comps = URLComponents()
        comps.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.percentEncodedQuery?.data(using: .utf8)
    }

    private func makeRequest(params: [String: String]) throws -> URLRequest {
        guard let url = URL(string: LastFMDefaults.baseUrl) else { throw LastFMError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Trop/1.0 (https://github.com/686udjie/Trop)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let body = formBody(params: params, secret: LastFMDefaults.secret) else {
            throw LastFMError.invalidResponse
        }
        req.httpBody = body
        return req
    }

    private func perform<T: Decodable>(_ params: [String: String], decode: T.Type) async throws -> T {
        let req = try makeRequest(params: params)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw LastFMError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? ""

        // Check for API error embedded in 200 response
        if let errorObj = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data), errorObj.error != 0 {
            // Distinguish unauthorized token (14) for webview flow
            if errorObj.error == 14 {
                throw LastFMError.unauthorizedToken
            }
            throw LastFMError.api(errorObj.error, errorObj.message)
        }

        if !(200...299).contains(status) {
            // Try to decode error
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                throw LastFMError.api(err.error, err.message)
            }
            throw LastFMError.http(status, bodyStr)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Try raw text contains error?
            if bodyStr.contains("\"error\""),
               let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                if err.error == 14 { throw LastFMError.unauthorizedToken }
                throw LastFMError.api(err.error, err.message)
            }
            throw LastFMError.network(error)
        }
    }

    // MARK: - Public API

    func getToken() async throws -> String {
        let params: [String: String] = [
            "method": "auth.getToken",
            "api_key": LastFMDefaults.apiKey
        ]
        let resp: LastFMTokenResponse = try await perform(params, decode: LastFMTokenResponse.self)
        return resp.token
    }

    func getSession(token: String) async throws -> LastFMAuthResponse {
        let params: [String: String] = [
            "method": "auth.getSession",
            "api_key": LastFMDefaults.apiKey,
            "token": token
        ]
        return try await perform(params, decode: LastFMAuthResponse.self)
    }

    func getMobileSession(username: String, password: String) async throws -> LastFMAuthResponse {
        let params: [String: String] = [
            "method": "auth.getMobileSession",
            "api_key": LastFMDefaults.apiKey,
            "username": username,
            "password": password
        ]
        return try await perform(params, decode: LastFMAuthResponse.self)
    }

    func updateNowPlaying(artist: String, track: String, album: String?, trackNumber: Int?, duration: Int?) async throws {
        guard let sk = sessionKey, !sk.isEmpty else { throw LastFMError.missingSession }
        var extra: [String: String] = [
            "artist": artist,
            "track": track,
            "sk": sk
        ]
        if let album, !album.isEmpty { extra["album"] = album }
        if let n = trackNumber { extra["trackNumber"] = String(n) }
        if let d = duration { extra["duration"] = String(d) }
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": LastFMDefaults.apiKey
        ]
        for (k, v) in extra { params[k] = v }
        // We don't need decoded response; use generic JSON
        struct Empty: Codable {}
        _ = try await perform(params, decode: Empty.self) as Empty
    }

    // swiftlint:disable:next function_parameter_count
    func scrobble(artist: String, track: String, timestamp: Int64, album: String?, trackNumber: Int?, duration: Int?) async throws {
        guard let sk = sessionKey, !sk.isEmpty else { throw LastFMError.missingSession }
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": LastFMDefaults.apiKey,
            "sk": sk,
            "artist[0]": artist,
            "track[0]": track,
            "timestamp[0]": String(timestamp)
        ]
        if let album, !album.isEmpty { params["album[0]"] = album }
        if let n = trackNumber { params["trackNumber[0]"] = String(n) }
        if let d = duration { params["duration[0]"] = String(d) }
        struct Empty: Codable {}
        _ = try await perform(params, decode: Empty.self) as Empty
    }

    func setLoveStatus(artist: String, track: String, love: Bool) async throws {
        guard let sk = sessionKey, !sk.isEmpty else { throw LastFMError.missingSession }
        let method = love ? "track.love" : "track.unlove"
        let params: [String: String] = [
            "method": method,
            "api_key": LastFMDefaults.apiKey,
            "sk": sk,
            "artist": artist,
            "track": track
        ]
        struct Empty: Codable {}
        _ = try await perform(params, decode: Empty.self) as Empty
    }

    // MARK: - Avatar

    struct UserGetInfoResponse: Codable {
        let user: LastFMUserDetail
    }

    struct LastFMUserDetail: Codable {
        let name: String
        let image: [LastFMImage]?
        let url: String?
    }

    struct LastFMImage: Codable {
        let size: String
        // swiftlint:disable:next identifier_name
        let text: String
        enum CodingKeys: String, CodingKey {
            case size
            case text = "#text"
        }
    }

    /// Fetches avatar URL via `user.getInfo` (no signature needed). Mirrors Discord's avatar fetch.
    func fetchAvatarURL(username: String) async -> URL? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.lastfm.warning("fetchAvatarURL: empty username")
            return nil
        }
        guard LastFMDefaults.isConfigured else {
            Log.lastfm.warning("fetchAvatarURL: API keys not configured")
            return nil
        }
        var comps = URLComponents(string: LastFMDefaults.baseUrl)
        comps?.queryItems = [
            URLQueryItem(name: "method", value: "user.getInfo"),
            URLQueryItem(name: "user", value: trimmed),
            URLQueryItem(name: "api_key", value: LastFMDefaults.apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps?.url else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Trop/1.0 (https://github.com/686udjie/Trop)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                return nil
            }
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data), err.error != 0 {
                return nil
            }
            let decoded = try JSONDecoder().decode(UserGetInfoResponse.self, from: data)
            let images = decoded.user.image ?? []
            let preference = ["extralarge", "large", "medium", "small"]
            for pref in preference {
                if let match = images.first(where: { $0.size == pref && !$0.text.isEmpty }) {
                    return URL(string: match.text)
                }
            }
            if let any = images.first(where: { !$0.text.isEmpty }) {
                return URL(string: any.text)
            }
            return nil
        } catch {
            return nil
        }
    }
}
