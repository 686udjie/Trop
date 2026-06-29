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
            // Generate PoToken for web clients that need it
            var playerPoToken: String?
            var streamPoToken: String?

            if fb.client.useWebPoTokens {
                do {
                    let tokens = try await generatePoToken(videoId: videoId)
                    playerPoToken = tokens.playerRequestPoToken
                    streamPoToken = tokens.streamingDataPoToken
                    print("[PlaybackManager] Got PoToken for \(fb.client.clientName)")
                } catch {
                    print("[PlaybackManager] PoToken generation failed for \(fb.client.clientName): \(error.localizedDescription)")
                }
            }

            do {
                let result = try await StreamResolver.resolve(
                    videoId: videoId,
                    client: fb.client,
                    poToken: playerPoToken,
                    streamingDataPoToken: streamPoToken
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

    /// Generate PoToken for the given video. Returns playerRequestPoToken and streamingDataPoToken.
    private func generatePoToken(videoId: String) async throws -> PoTokenResult {
        let sessionId = await getSessionId()
        return try await PoTokenGenerator.shared.generate(
            videoId: videoId,
            sessionId: sessionId
        )
    }

    private func getSessionId() async -> String? {
        // Use visitorData from InnerTube as session identifier
        "SESSION"
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
            var playerPoToken: String?
            var streamPoToken: String?

            if fb.client.useWebPoTokens {
                do {
                    let tokens = try await generatePoToken(videoId: videoId)
                    playerPoToken = tokens.playerRequestPoToken
                    streamPoToken = tokens.streamingDataPoToken
                } catch {
                    print("[PlaybackManager] PoToken gen failed for \(fb.client.clientName): \(error.localizedDescription)")
                }
            }

            do {
                let result = try await StreamResolver.resolve(
                    videoId: videoId,
                    client: fb.client,
                    poToken: playerPoToken,
                    streamingDataPoToken: streamPoToken
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
