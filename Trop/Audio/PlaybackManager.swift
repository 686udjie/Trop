//
//  PlaybackManager.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// Resolves streams and hands off to PlayerController, trying the client fallback chain.
actor PlaybackManager {
    static let shared = PlaybackManager()

    private var inflightResolutions: [String: Task<PlaybackResult, Error>] = [:]

    private init() {}

    /// Resolve a video and start playback. Returns the result used, or throws.
    @discardableResult
    func resolveAndPlay(videoId: String) async throws -> PlaybackResult {
        if let localPath = await DownloadManager.shared.localURL(for: videoId) {
            let song = NowPlaying.shared.queueSongs.first { $0.videoId == videoId }
            let artists = song?.artists ?? []
            await PlayerController.shared.play(
                url: localPath.absoluteString,
                title: song?.title,
                artist: song?.artists.map(\.name).joined(separator: ", "),
                videoId: videoId,
                duration: song.map { TimeInterval($0.duration) },
                artists: artists
            )
            return PlaybackResult(
                streamUrl: localPath.absoluteString,
                itag: 0,
                mimeType: "audio/mp4",
                bitrate: 0,
                audioQuality: "local",
                videoId: videoId,
                title: song?.title,
                author: song?.artists.map(\.name).joined(separator: ", "),
                duration: song?.duration,
                expiresInSeconds: Int.max,
                clientName: "local",
                musicVideoType: nil,
                hasVideoContent: false,
                muxedStreamUrl: nil
            )
        }

        if let existing = inflightResolutions[videoId] {
            return try await existing.value
        }

        if let cached = await StreamCache.shared.get(videoId: videoId) {
            await PlayerController.shared.play(
                url: cached.streamUrl,
                title: cached.title,
                artist: cached.author,
                videoId: videoId,
                duration: cached.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                artists: queueArtists(for: videoId)
            )
            return cached
        }

        // Pre-generate PoToken in background while direct-URL clients are tried
        let poTokenTask = Task { try? await generatePoToken(videoId: videoId) }
        defer { poTokenTask.cancel() }

        var lastError: Error?

        for fb in ClientFallbackChain.preferred {
            var playerPoToken: String?
            var streamPoToken: String?

            if fb.client.useWebPoTokens {
                if let tokens = await poTokenTask.value {
                    playerPoToken = tokens.playerRequestPoToken
                    streamPoToken = tokens.streamingDataPoToken
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
                    await StreamCache.shared.set(videoId: videoId, result: result)
                    await PlayerController.shared.play(
                        url: result.streamUrl,
                        title: result.title,
                        artist: result.author,
                        videoId: videoId,
                        duration: result.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                        artists: queueArtists(for: videoId)
                    )
                    if let musicVideoType = result.musicVideoType {
                        await MainActor.run {
                            NowPlaying.shared.updateVideoAvailability(
                                musicVideoType: musicVideoType,
                                hasVideoContent: result.hasVideoContent
                            )
                        }
                    } else {
                        await MainActor.run {
                            NowPlaying.shared.updateVideoAvailability(hasVideoContent: result.hasVideoContent)
                        }
                    }
                    return result
                }

                guard await StreamResolver.validateStream(url: result.streamUrl) else {
                    Log.playbackManager.debug("\(result.clientName) HEAD validation failed, trying next")
                    lastError = StreamError.validationFailed(result.clientName)
                    continue
                }

                await PlayerController.shared.play(
                    url: result.streamUrl,
                    title: result.title,
                    artist: result.author,
                    videoId: videoId,
                    duration: result.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                    artists: queueArtists(for: videoId)
                )
                if let musicVideoType = result.musicVideoType {
                    await MainActor.run {
                        NowPlaying.shared.updateVideoAvailability(
                            musicVideoType: musicVideoType,
                            hasVideoContent: result.hasVideoContent
                        )
                    }
                } else {
                    await MainActor.run {
                        NowPlaying.shared.updateVideoAvailability(hasVideoContent: result.hasVideoContent)
                    }
                }
                return result

            } catch {
                lastError = error
                Log.playbackManager.error("\(fb.client.clientName) failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? StreamError.allClientsFailed
    }

    private func clearInflight(videoId: String) {
        inflightResolutions.removeValue(forKey: videoId)
    }

    /// Retrieves all artists for the current video to preserve metadata accuracy.
    private func queueArtists(for videoId: String) -> [YTArtist] {
        NowPlaying.shared.queueSongs.first { $0.videoId == videoId }?.artists ?? []
    }

    /// Resolves the muxed (audio+video) stream URL for video mode.
    func resolveVideoStream(videoId: String) async throws -> String {
        for fb in ClientFallbackChain.preferred {
            do {
                let signatureTimestamp: Int?
                if fb.client.useSignatureTimestamp {
                    signatureTimestamp = try? await PlayerJsFetcher.shared.getSignatureTimestamp()
                } else {
                    signatureTimestamp = nil
                }

                let response = try await InnerTube.shared.playerResponse(
                    videoId: videoId,
                    client: fb.client,
                    signatureTimestamp: signatureTimestamp,
                    poToken: nil
                )

                guard let streamingData = response.streamingData else {
                    continue
                }

                let allFormats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])

                if let videoFormat = FormatSelector.bestVideoFormat(from: allFormats),
                   let url = videoFormat.url {
                    return url
                }
            } catch {
                Log.playbackManager.error("Video resolution failed for \(fb.client.clientName): \(error)")
            }
        }

        throw StreamError.noSuitableFormat
    }

    /// Returns the cached audio-only stream URL, re-resolving if not cached.
    func resolveAndPlayAudioURL(videoId: String) async throws -> String {
        if let cached = await StreamCache.shared.get(videoId: videoId) {
            return cached.streamUrl
        }
        let result = try await resolve(videoId: videoId)
        return result.streamUrl
    }

    /// Returns the muxed stream URL for video mode, preferring the cached one.
    func resolveMuxedURL(videoId: String) async throws -> String {
        if let cached = await StreamCache.shared.get(videoId: videoId),
           let muxed = cached.muxedStreamUrl {
            return muxed
        }
        return try await resolveVideoStream(videoId: videoId)
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
    func resolve(videoId: String, preferredFormat: Format? = nil, forDownload: Bool = false) async throws -> PlaybackResult {
        if let existing = inflightResolutions[videoId] {
            return try await existing.value
        }

        if let cached = await StreamCache.shared.get(videoId: videoId) {
            return cached
        }

        let poTokenTask = Task { try? await generatePoToken(videoId: videoId) }
        defer { poTokenTask.cancel() }

        var lastError: Error?

        for fb in ClientFallbackChain.preferred {
            var playerPoToken: String?
            var streamPoToken: String?

            if fb.client.useWebPoTokens {
                playerPoToken = await poTokenTask.value?.playerRequestPoToken
                streamPoToken = await poTokenTask.value?.streamingDataPoToken
            }

            do {
                let result = try await StreamResolver.resolve(
                    videoId: videoId,
                    client: fb.client,
                    poToken: playerPoToken,
                    streamingDataPoToken: streamPoToken,
                    preferredFormat: preferredFormat,
                    forDownload: forDownload
                )

                if fb.skipValidation {
                    await StreamCache.shared.set(videoId: videoId, result: result)
                    return result
                }

                guard await StreamResolver.validateStream(url: result.streamUrl) else {
                    lastError = StreamError.validationFailed(result.clientName)
                    continue
                }

                await StreamCache.shared.set(videoId: videoId, result: result)
                return result

            } catch {
                lastError = error
                Log.playbackManager.error("\(fb.client.clientName) failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? StreamError.allClientsFailed
    }
}
