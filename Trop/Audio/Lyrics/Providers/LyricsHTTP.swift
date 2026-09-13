//
//  LyricsHTTP.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation

/// Shared request boilerplate for lyrics providers: perform the request,
/// require HTTP 200 (anything else is `.notFound`), and decode the body.
/// Preserves each provider's exact error contract — headers, query building
/// and response interpretation stay per-provider.
enum LyricsHTTP {
    /// GETs `request`, throwing `.notFound` unless the status is exactly 200.
    static func get(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LyricsError.notFound
        }
        return data
    }

    /// `get` + JSON dictionary decode, throwing `.decodingFailed` on bad JSON.
    static func getJSON(_ request: URLRequest) async throws -> [String: Any] {
        let data = try await get(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LyricsError.decodingFailed
        }
        return json
    }

    /// `get` + `Decodable` decode, throwing `.decodingFailed` on bad JSON.
    static func decoded<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let data = try await get(request)
        guard let decoded = try? JSONDecoder().decode(type, from: data) else {
            throw LyricsError.decodingFailed
        }
        return decoded
    }
}

/// Shared plain-text line splitting for lyrics providers.
enum LyricsText {
    /// Splits on newlines, trims, drops empties — untimed lines.
    static func plainLines(_ s: String) -> [LyricLine] {
        s.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(text: $0, startTime: nil) }
    }
}
