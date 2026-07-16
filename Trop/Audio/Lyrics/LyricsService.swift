//
//  LyricsService.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval?

    static let placeholder = LyricLine(text: "♪", startTime: nil)
}

actor LyricsService {
    static let shared = LyricsService()

    private init() {}

    func fetchLyrics(videoId: String) async throws -> [LyricLine] {
        // TODO: Implement lyrics fetching.
        return []
    }
}
