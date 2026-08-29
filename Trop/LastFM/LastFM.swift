//
//  LastFM.swift
//  Trop
//

import CryptoKit
import Foundation

enum LastFMError: Error, LocalizedError {
    case notConfigured
    case notLoggedIn
    case api(code: Int, message: String)
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Last.fm API credentials are not configured in Trop.plist"
        case .notLoggedIn:
            return "Not logged in to Last.fm"
        case .api(_, let message):
            return message
        case .invalidResponse:
            return "Invalid response from Last.fm"
        case .network(let error):
            return error.localizedDescription
        }
    }
}

struct LastFMTokenResponse: Decodable {
    let token: String
}

struct LastFMAuthentication: Decodable {
    let session: Session

    struct Session: Decodable {
        let name: String
        let key: String
        let subscriber: Int?
    }
}

struct LastFMAPIErrorBody: Decodable {
    let error: Int
    let message: String
}

/// Signed Last.fm API 2.0 client (Metrolist-compatible).
enum LastFMDefaults {
    static let scrobbleDelayPercent: Double = 0.5
    static let scrobbleDelaySeconds: TimeInterval = 180
    static let scrobbleMinSongDuration: TimeInterval = 30
}

actor LastFM {
    static let shared = LastFM()

    static let defaultScrobbleDelayPercent = LastFMDefaults.scrobbleDelayPercent
    static let defaultScrobbleDelaySeconds = LastFMDefaults.scrobbleDelaySeconds
    static let defaultScrobbleMinSongDuration = LastFMDefaults.scrobbleMinSongDuration

    private let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let session: URLSession
    private let decoder: JSONDecoder

    private var apiKey = ""
    private var apiSecret = ""
    private var sessionKey: String?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    static func initialize(apiKey: String, secret: String) {
        Task {
            await shared.configure(apiKey: apiKey, apiSecret: secret, sessionKey: nil)
        }
    }

    func configure(apiKey: String, apiSecret: String, sessionKey: String?) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.sessionKey = sessionKey
    }

    func setSessionKey(_ key: String?) {
        sessionKey = key
    }

    var isConfigured: Bool {
        !apiKey.isEmpty && !apiSecret.isEmpty
    }

    var isLoggedIn: Bool {
        isConfigured && !(sessionKey ?? "").isEmpty
    }

    func getToken() async throws -> String {
        guard isConfigured else { throw LastFMError.notConfigured }
        let data = try await post(method: "auth.getToken", extra: [:], includeSession: false)
        if let error = try? decoder.decode(LastFMAPIErrorBody.self, from: data), error.error != 0 {
            throw LastFMError.api(code: error.error, message: error.message)
        }
        let response = try decoder.decode(LastFMTokenResponse.self, from: data)
        return response.token
    }

    func getSession(token: String) async throws -> LastFMAuthentication {
        guard isConfigured else { throw LastFMError.notConfigured }
        let data = try await post(
            method: "auth.getSession",
            extra: ["token": token],
            includeSession: false
        )
        if let error = try? decoder.decode(LastFMAPIErrorBody.self, from: data), error.error != 0 {
            throw LastFMError.api(code: error.error, message: error.message)
        }
        do {
            let auth = try decoder.decode(LastFMAuthentication.self, from: data)
            sessionKey = auth.session.key
            return auth
        } catch {
            throw LastFMError.invalidResponse
        }
    }

    func authURL(token: String) -> URL {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url!
    }

    func updateNowPlaying(
        artist: String,
        track: String,
        album: String? = nil,
        duration: Int? = nil
    ) async throws {
        guard isLoggedIn else { throw LastFMError.notLoggedIn }
        var extra: [String: String] = [
            "artist": artist,
            "track": track
        ]
        if let album, !album.isEmpty { extra["album"] = album }
        if let duration, duration > 0 { extra["duration"] = String(duration) }
        _ = try await post(method: "track.updateNowPlaying", extra: extra, includeSession: true)
    }

    func scrobble(
        artist: String,
        track: String,
        timestamp: Int,
        album: String? = nil,
        duration: Int? = nil
    ) async throws {
        guard isLoggedIn else { throw LastFMError.notLoggedIn }
        var extra: [String: String] = [
            "artist[0]": artist,
            "track[0]": track,
            "timestamp[0]": String(timestamp)
        ]
        if let album, !album.isEmpty { extra["album[0]"] = album }
        if let duration, duration > 0 { extra["duration[0]"] = String(duration) }
        _ = try await post(method: "track.scrobble", extra: extra, includeSession: true)
    }

    // MARK: - Request plumbing

    private func post(
        method: String,
        extra: [String: String],
        includeSession: Bool
    ) async throws -> Data {
        var params: [String: String] = [
            "method": method,
            "api_key": apiKey
        ]
        params.merge(extra) { _, new in new }
        if includeSession, let sessionKey {
            params["sk"] = sessionKey
        }
        params["api_sig"] = apiSig(for: params)
        params["format"] = "json"

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Trop (https://github.com/686udjie/Trop)", forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody(params)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LastFMError.invalidResponse
            }
            if http.statusCode >= 400 {
                if let error = try? decoder.decode(LastFMAPIErrorBody.self, from: data) {
                    throw LastFMError.api(code: error.error, message: error.message)
                }
                throw LastFMError.invalidResponse
            }
            if let error = try? decoder.decode(LastFMAPIErrorBody.self, from: data),
               error.error != 0 {
                throw LastFMError.api(code: error.error, message: error.message)
            }
            return data
        } catch let error as LastFMError {
            throw error
        } catch {
            throw LastFMError.network(error)
        }
    }

    private func apiSig(for params: [String: String]) -> String {
        let sorted = params.keys.sorted()
        let concatenated = sorted.map { $0 + (params[$0] ?? "") }.joined() + apiSecret
        let digest = Insecure.MD5.hash(data: Data(concatenated.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}
