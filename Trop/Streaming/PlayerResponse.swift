//
//  PlayerResponse.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Top-level response from POST /player
struct PlayerResponse: Decodable {
    let responseContext: ResponseContext?
    let playabilityStatus: PlayabilityStatus?
    let streamingData: StreamingData?
    let videoDetails: VideoDetails?
    let playbackTracking: PlaybackTracking?

    // Simplified status check
    var isPlayable: Bool {
        playabilityStatus?.status == "OK"
    }
}

struct ResponseContext: Decodable {
    let serviceTrackingParams: [ServiceTrackingParam]?
}

struct ServiceTrackingParam: Decodable {
    let service: String?
    let params: [TrackingParam]?
}

struct TrackingParam: Decodable {
    let key: String?
    let value: String?
}

// Playability information
struct PlayabilityStatus: Decodable {
    let status: String?
    let reason: String?
}

// Streaming data containing available formats
struct StreamingData: Decodable {
    let formats: [Format]?
    let adaptiveFormats: [Format]?
    let expiresInSeconds: String?

    var expiresInSecondsValue: Int? {
        expiresInSeconds.flatMap { Int($0) }
    }
}

// Individual stream format (audio or video)
struct Format: Decodable {
    let itag: Int?
    let url: String?
    let mimeType: String?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let contentLength: String?
    let quality: String?
    let averageBitrate: Int?
    let audioQuality: String?
    let audioChannels: Int?
    let approxDurationMs: String?
    let loudnessDb: Double?
    let lastModified: String?
    let signatureCipher: String?
    let cipher: String?

    var isAudioOnly: Bool {
        width == nil
    }

    var codec: String {
        guard let mimeType else { return "" }
        // Extract codec from e.g. "audio/webm; codecs=\"opus\""
        if let codecsRange = mimeType.range(of: "codecs=\"") {
            let afterPrefix = mimeType[codecsRange.upperBound...]
            if let endQuote = afterPrefix.firstIndex(of: "\"") {
                return String(afterPrefix[..<endQuote])
            }
        }
        return mimeType
    }
}

// Video metadata
struct VideoDetails: Decodable {
    let videoId: String?
    let title: String?
    let author: String?
    let channelId: String?
    let lengthSeconds: String?
    let musicVideoType: String?
    let viewCount: String?
    let thumbnail: ThumbnailInfo?
}

struct ThumbnailInfo: Decodable {
    let thumbnails: [ThumbnailImage]?
}

struct ThumbnailImage: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

// Playback tracking URLs (for Milestone 7)
struct PlaybackTracking: Decodable {
    let videostatsPlaybackUrl: TrackingUrl?
    let videostatsWatchtimeUrl: TrackingUrl?
}

struct TrackingUrl: Decodable {
    let baseUrl: String?
}
