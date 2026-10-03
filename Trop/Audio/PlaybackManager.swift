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
        var request = StreamResolveRequest.playback(videoId: videoId)
        request.options.audioQuality = SettingsStore.shared.audioQuality
        let result = try await StreamFallback.resolveFirstValid(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        )
        await playNetworkResult(result, videoId: videoId)
        return result
    }

    private func playNetworkResult(_ result: PlaybackResult, videoId: String) async {
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
        var request = StreamResolveRequest(videoId: videoId)
        request.options.audioQuality = SettingsStore.shared.audioQuality
        switch try await StreamFallback.resolveVideo(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        ) {
        case .muxed(let url):
            return url
        case .split(let videoURL, let audioURL, let duration):
            return StreamFallback.combineVideoAndAudio(
                videoURL: videoURL,
                audioURL: audioURL,
                duration: duration
            )
        }
    }

    /// Returns the muxed/video stream URL for video mode, preferring the cached one.
    func resolveMuxedURL(videoId: String) async throws -> String {
        if let cached = await StreamCache.shared.get(videoId: videoId),
           let muxed = cached.muxedStreamUrl {
            return muxed
        }
        return try await resolveVideoStream(videoId: videoId)
    }

    func resolveVideoOnlyURL(videoId: String) async throws -> String {
        let request = StreamResolveRequest(videoId: videoId)
        switch try await StreamFallback.resolveVideo(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        ) {
        case .muxed(let url):
            return url
        case .split(let videoURL, _, _):
            return videoURL
        }
    }

    /// Stable per-launch session id for PoToken minting.
    static let sessionId: String = UUID().uuidString
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
        var request = forDownload ? StreamResolveRequest.download(videoId: videoId) : .playback(videoId: videoId)
        request.options.preferredFormat = preferredFormat
        request.options.audioQuality = SettingsStore.shared.audioQuality
        request.options.downloadQuality = SettingsStore.shared.downloadQuality
        return try await StreamFallback.resolveFirstValid(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        )
    }
}
