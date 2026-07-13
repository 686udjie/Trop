//
// RegisterPlaybackService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation

actor RegisterPlaybackService {
    nonisolated static let shared = RegisterPlaybackService()
    private let innerTube = InnerTube.shared

    private init() {}

    func registerPlayback(url: String) async throws {
        print("[RegisterPlayback] Delegating to InnerTube for YTM tracking")
        try await innerTube.registerPlayback(trackingUrl: url)
    }
}
