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

    private func resolutionKey(videoId: String, forDownload: Bool) -> String {
        forDownload ? "\(videoId):download" : videoId
    }

    private init() {}

    /// Resolve a video and start playback. Returns the result used, or throws.
    @discardableResult
    func resolveAndPlay(videoId: String) async throws -> PlaybackResult {
        if let localPath = await DownloadManager.shared.localURL(for: videoId) {
            let song = await MainActor.run { NowPlaying.shared.queueSongs.first { $0.videoId == videoId } }
            let artists = song?.artists ?? []
            await PlayerController.shared.play(
                url: localPath.absoluteString,
                title: song?.title,
                artist: song?.artists.map(\.name).joined(separator: ", "),
                videoId: videoId,
                duration: song.map { TimeInterval($0.duration) },
                artists: artists
            )
            await MainActor.run {
                NowPlaying.shared.updateVideoAvailability(hasVideoContent: false)
            }
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
                muxedStreamUrl: nil,
                loudnessDb: nil
            )
        }

        if let cached = await StreamCache.shared.get(videoId: videoId) {
            await PlayerController.shared.play(
                url: cached.streamUrl,
                title: cached.title,
                artist: cached.author,
                videoId: videoId,
                duration: cached.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                artists: await queueArtists(for: videoId),
                loudnessDb: cached.loudnessDb
            )
            if let musicVideoType = cached.musicVideoType {
                await MainActor.run {
                    NowPlaying.shared.updateVideoAvailability(
                        musicVideoType: musicVideoType,
                        hasVideoContent: cached.hasVideoContent
                    )
                }
            } else {
                await MainActor.run {
                    NowPlaying.shared.updateVideoAvailability(hasVideoContent: cached.hasVideoContent)
                }
            }
            return cached
        }

        if let existing = inflightResolutions[videoId] {
            return try await existing.value
        }

        let task = Task { [self] in
            try await resolveAndPlayFromNetwork(videoId: videoId)
        }
        inflightResolutions[videoId] = task
        defer { clearInflight(key: videoId) }
        return try await task.value
    }

    /// Runs the client fallback chain for playback. Only called once per
    /// videoId by `resolveAndPlay`, which owns the in-flight dedup entry.
    private func resolveAndPlayFromNetwork(videoId: String) async throws -> PlaybackResult {
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
                        artists: await queueArtists(for: videoId),
                        loudnessDb: result.loudnessDb
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

                await StreamCache.shared.set(videoId: videoId, result: result)
                await PlayerController.shared.play(
                    url: result.streamUrl,
                    title: result.title,
                    artist: result.author,
                    videoId: videoId,
                    duration: result.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                    artists: await queueArtists(for: videoId),
                    loudnessDb: result.loudnessDb
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

    private func clearInflight(key: String) {
        inflightResolutions.removeValue(forKey: key)
    }

    /// Retrieves all artists for the current video to preserve metadata accuracy.
    private func queueArtists(for videoId: String) async -> [YTArtist] {
        await MainActor.run {
            NowPlaying.shared.queueSongs.first { $0.videoId == videoId }?.artists ?? []
        }
    }

    /// Resolves a playable video stream URL for video mode. Prefers a muxed
    /// (audio+video) stream; when the video offers none, falls back to an EDL
    /// that combines a DASH video-only stream with a separate audio stream.
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

                if let muxed = FormatSelector.bestVideoFormat(from: allFormats),
                   let url = muxed.url {
                    return url
                }

                if let video = FormatSelector.bestVideoOnlyFormat(from: allFormats),
                   let videoURL = video.url,
                   let audio = FormatSelector.bestAudioFormat(from: allFormats, preference: SettingsStore.shared.audioQuality),
                   let audioURL = try? await Self.resolveStreamURL(audio) {
                    let duration = response.videoDetails?.lengthSeconds.flatMap(Int.init)
                    return Self.combineVideoAndAudio(videoURL: videoURL, audioURL: audioURL, duration: duration)
                }
            } catch {
                Log.playbackManager.error("Video resolution failed for \(fb.client.clientName): \(error)")
            }
        }

        throw StreamError.noSuitableFormat
    }

    /// Returns the muxed/video stream URL for video mode, preferring the cached one.
    func resolveMuxedURL(videoId: String) async throws -> String {
        if let cached = await StreamCache.shared.get(videoId: videoId),
           let muxed = cached.muxedStreamUrl {
            return muxed
        }
        return try await resolveVideoStream(videoId: videoId)
    }

    /// Resolves a format's stream URL, going through the cipher if needed.
    private static func resolveStreamURL(_ format: Format) async throws -> String {
        if let url = format.url, !url.isEmpty { return url }
        if let cipherText = format.signatureCipher ?? format.cipher {
            let playerJs = try await PlayerJsFetcher.shared.getPlayerJs()
            return try await CipherExecutor.shared.resolveCipherURL(
                cipherText: cipherText,
                playerJs: playerJs,
                playerHash: nil
            )
        }
        throw StreamError.noStreamUrl
    }

    /// Builds an EDL that sources the video and audio tracks from two separate
    /// DASH streams, mirroring how mpv's ytdl hook plays split YouTube streams.
    /// URLs are embedded with mpv's `%<len>%<url>` escape so any characters
    /// (semicolons, commas, etc.) survive EDL parsing verbatim. `duration`
    /// (when known) pins each part's timeline length so mpv does not end
    /// playback early when a stream's duration cannot be probed.
    private static func combineVideoAndAudio(videoURL: String, audioURL: String, duration: Int?) -> String {
        let lengthParam = duration.map { ",length=\($0)" } ?? ""
        let video = "%\(videoURL.utf8.count)%\(videoURL)\(lengthParam)"
        let audio = "%\(audioURL.utf8.count)%\(audioURL)\(lengthParam)"
        return "edl://!new_stream;!no_clip;!no_chapters;\(video);!new_stream;!no_clip;!no_chapters;\(audio)"
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
        if !forDownload, let cached = await StreamCache.shared.get(videoId: videoId) {
            return cached
        }

        let key = resolutionKey(videoId: videoId, forDownload: forDownload)
        if let existing = inflightResolutions[key] {
            return try await existing.value
        }

        let task = Task { [self] in
            try await resolveFromNetwork(videoId: videoId, preferredFormat: preferredFormat, forDownload: forDownload)
        }
        inflightResolutions[key] = task
        defer { clearInflight(key: key) }
        return try await task.value
    }

    private func resolveFromNetwork(videoId: String, preferredFormat: Format?, forDownload: Bool) async throws -> PlaybackResult {
        var poTokenTask: Task<PoTokenResult?, Never>?
        defer { poTokenTask?.cancel() }

        var lastError: Error?
        var nonAACFallback: PlaybackResult?
        let clients = forDownload ? ClientFallbackChain.forDownload : ClientFallbackChain.preferred

        for fb in clients {
            var playerPoToken: String?
            var streamPoToken: String?

            if fb.client.useWebPoTokens {
                if poTokenTask == nil {
                    poTokenTask = Task { try? await generatePoToken(videoId: videoId) }
                }
                playerPoToken = await poTokenTask?.value?.playerRequestPoToken
                streamPoToken = await poTokenTask?.value?.streamingDataPoToken
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

                if !fb.skipValidation {
                    guard await StreamResolver.validateStream(url: result.streamUrl) else {
                        lastError = StreamError.validationFailed(result.clientName)
                        Log.playbackManager.debug("\(result.clientName) HEAD validation failed, trying next")
                        continue
                    }
                }

                // Downloads remux/transcode with AVFoundation; prefer AAC so we
                // can skip Opus→AAC (unreliable in Simulator / some devices).
                if forDownload {
                    let mime = result.mimeType.lowercased()
                    let isAAC = mime.contains("mp4a") || mime.contains("aac")
                    if !isAAC {
                        Log.playbackManager.debug(
                            "\(result.clientName) returned non-AAC (\(result.mimeType)); looking for AAC client"
                        )
                        nonAACFallback = result
                        continue
                    }
                } else {
                    await StreamCache.shared.set(videoId: videoId, result: result)
                }
                return result

            } catch {
                lastError = error
                Log.playbackManager.error("\(fb.client.clientName) failed: \(error.localizedDescription)")
            }
        }

        if forDownload, let fallback = nonAACFallback {
            Log.playbackManager.debug("No AAC stream found — falling back to \(fallback.mimeType)")
            return fallback
        }

        throw lastError ?? StreamError.allClientsFailed
    }
}
