//
//  LRCLIBProvider.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

struct LRCLIBProvider: LyricsProvider {
    let id = "lrclib"
    let name = "LRCLIB"

    private let baseURL = "https://lrclib.net/api/get"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        var components = URLComponents(string: baseURL)!
        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "album_name", value: query.album ?? "")
        ]
        if query.durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(query.durationSeconds)))
        }
        components.queryItems = items

        guard let url = components.url else { throw LyricsError.invalidURL }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LyricsError.notFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LyricsError.decodingFailed
        }

        if let instrumental = json["instrumental"] as? Bool, instrumental {
            return [LyricLine(text: "♪ Instrumental ♪", startTime: nil)]
        }

        if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = LyricsParsing.parseLrc(synced)
            if !lines.isEmpty { return lines }
        }

        if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
            let lines = plain
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { LyricLine(text: $0, startTime: nil) }
            if !lines.isEmpty { return lines }
        }

        throw LyricsError.notFound
    }
}

enum LyricsError: Error, LocalizedError {
    case invalidURL
    case notFound
    case decodingFailed
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid lyrics request URL"
        case .notFound: return "Lyrics not found"
        case .decodingFailed: return "Failed to decode lyrics response"
        case .requestFailed(let code): return "Lyrics request failed (HTTP \(code))"
        }
    }
}
