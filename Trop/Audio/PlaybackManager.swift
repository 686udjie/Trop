//
//  PlaybackManager.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// Orchestrates stream resolution → playback.
/// Tries the fallback client chain, caches results, and hands off to PlayerController.
actor PlaybackManager {
    static let shared = PlaybackManager()

    private init() {}

    /// Resolve a video and start playback. Returns the result used, or throws.
    @discardableResult
    func resolveAndPlay(videoId: String) async throws -> PlaybackResult {
        // 1. Check cache first
        if let cached = await StreamCache.shared.get(videoId: videoId) {
            print("[PlaybackManager] Cache hit for videoId=\(videoId)")
            PlayerController.shared.play(
                url: cached.streamUrl,
                title: cached.title,
                artist: cached.author
            )
            return cached
        }

        // 2. Resolve via fallback chain
        var lastError: Error?

        for fb in ClientFallbackChain.preferred {
            do {
                let result = try await StreamResolver.resolve(
                    videoId: videoId,
                    client: fb.client
                )

                // Skip HEAD validation for clients marked skipValidation
                if fb.skipValidation {
                    print("[PlaybackManager] Using \(result.clientName) (skipped HEAD)")
                    await StreamCache.shared.set(videoId: videoId, result: result)
                    PlayerController.shared.play(
                        url: result.streamUrl,
                        title: result.title,
                        artist: result.author
                    )
                    return result
                }

                // HEAD validate for others
                guard await StreamResolver.validateStream(url: result.streamUrl) else {
                    print("[PlaybackManager] \(result.clientName) HEAD validation failed, trying next")
                    lastError = StreamError.validationFailed(result.clientName)
                    continue
                }

                print("[PlaybackManager] Using \(result.clientName) (HEAD validated)")
                await StreamCache.shared.set(videoId: videoId, result: result)
                PlayerController.shared.play(
                    url: result.streamUrl,
                    title: result.title,
                    artist: result.author
                )
                return result

            } catch {
                lastError = error
                print("[PlaybackManager] \(fb.client.clientName) failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? StreamError.allClientsFailed
    }

    /// Resolve a video without playing. Useful for previews / testing.
    func resolve(videoId: String) async throws -> PlaybackResult {
        // Check cache
        if let cached = await StreamCache.shared.get(videoId: videoId) {
            print("[PlaybackManager] Cache hit for videoId=\(videoId)")
            return cached
        }

        var lastError: Error?

        for fb in ClientFallbackChain.preferred {
            do {
                let result = try await StreamResolver.resolve(
                    videoId: videoId,
                    client: fb.client
                )

                if fb.skipValidation {
                    print("[PlaybackManager] Resolved with \(result.clientName) (no HEAD)")
                    await StreamCache.shared.set(videoId: videoId, result: result)
                    return result
                }

                guard await StreamResolver.validateStream(url: result.streamUrl) else {
                    print("[PlaybackManager] \(result.clientName) HEAD failed, trying next")
                    lastError = StreamError.validationFailed(result.clientName)
                    continue
                }

                print("[PlaybackManager] Resolved with \(result.clientName) (HEAD valid)")
                await StreamCache.shared.set(videoId: videoId, result: result)
                return result

            } catch {
                lastError = error
                print("[PlaybackManager] \(fb.client.clientName) failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? StreamError.allClientsFailed
    }
}
