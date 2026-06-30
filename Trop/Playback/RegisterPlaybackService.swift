//
// RegisterPlaybackService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation

actor RegisterPlaybackService {
    nonisolated static let shared = RegisterPlaybackService()
    private let session = URLSession(configuration: .default)

    private init() {}

    func registerPlayback(url: String) async throws {
        guard let requestUrl = URL(string: url) else {
            throw RegisterPlaybackError.invalidURL
        }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RegisterPlaybackError.httpError
        }
        print("[RegisterPlayback] Success: \(data.count) bytes")
    }
}

enum RegisterPlaybackError: Error, LocalizedError {
    case invalidURL
    case httpError
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid playback tracking URL"
        case .httpError: return "Playback registration request failed"
        }
    }
}
