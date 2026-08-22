//
//  FormatSelector.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Selects the best audio-only format from a list of adaptive formats
// using Metrolist's scoring algorithm:
//   1. audioQuality  (HIGH > MEDIUM > LOW)
//   2. audioChannels (higher = better)
//   3. codec         (opus > mp4a > other)
//   4. bitrate       (higher = better)
enum FormatSelector {

    /// The user's streaming-quality preference from settings. When non-`.auto`,
    /// formats at the preferred tier are selected first, falling back to the
    /// best available format when the preferred tier has no matches.
    static func bestAudioFormat(from formats: [Format], preference: AudioQuality = .auto) -> Format? {
        guard !formats.isEmpty else {
            Log.formatSelector.debug("No formats to select from")
            return nil
        }

        var audioFormats = formats.filter { $0.isAudioOnly }

        if audioFormats.isEmpty {
            Log.formatSelector.debug("No audio-only formats found in \(formats.count) total — trying combined formats with audio track")
            audioFormats = formats.filter { $0.audioChannels != nil }
        }

        guard !audioFormats.isEmpty else {
            Log.formatSelector.debug("No formats with audio track found in \(formats.count) total formats")
            return nil
        }

        if preference != .auto {
            let tier = Self.qualityTier(for: preference)
            let tierFormats = audioFormats.filter { Self.qualityRank($0.audioQuality) == tier }
            if !tierFormats.isEmpty {
                Log.formatSelector.debug("Preferring \(preference.rawValue) tier: \(tierFormats.count) format(s)")
                audioFormats = tierFormats
            } else {
                Log.formatSelector.debug("No \(preference.rawValue)-tier format, using best available")
            }
        }

        Log.formatSelector.debug("Selecting from \(audioFormats.count) audio-bearing formats")

        let selected = audioFormats.max { a, b in
            formatScore(a) < formatScore(b)
        }

        if let selected {
            Log.formatSelector.debug("Selected: itag=\(selected.itag ?? 0) quality=\(selected.audioQuality ?? "?")"
                + " channels=\(selected.audioChannels ?? 0) codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)")
        } else {
            Log.formatSelector.debug("No format could be selected")
        }

        return selected
    }

    /// Maps the user-facing quality preference to the format quality tier.
    private static func qualityTier(for preference: AudioQuality) -> Int {
        switch preference {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .auto: return 0
        }
    }

    /// Maps a format's `AUDIO_QUALITY_*` string to a comparable tier.
    private static func qualityRank(_ quality: String?) -> Int {
        switch quality {
        case "AUDIO_QUALITY_HIGH": return 3
        case "AUDIO_QUALITY_MEDIUM": return 2
        case "AUDIO_QUALITY_LOW": return 1
        default: return 0
        }
    }

    // Picks the optimal audio format for downloads
    static func bestDownloadFormat(from formats: [Format]) -> Format? {
        guard !formats.isEmpty else {
            Log.formatSelector.debug("No formats to select from (download)")
            return nil
        }

        var audioFormats = formats.filter { $0.isAudioOnly }

        if audioFormats.isEmpty {
            Log.formatSelector.debug("No audio-only formats found (download) — trying combined formats with audio")
            audioFormats = formats.filter { $0.audioChannels != nil }
        }

        guard !audioFormats.isEmpty else {
            Log.formatSelector.debug("No formats with audio track found (download)")
            return nil
        }

        let aacFormats = audioFormats.filter { format in
            let c = format.codec.lowercased()
            return c.contains("mp4a") || c.contains("aac")
        }

        let pool = aacFormats.isEmpty ? audioFormats : aacFormats
        Log.formatSelector.debug(
            "Download pool: \(pool.count) format(s)\(aacFormats.isEmpty ? " (no AAC, falling back to Opus)" : " (AAC preferred)")"
        )

        let selected = pool.max { a, b in
            formatScore(a) < formatScore(b)
        }

        if let selected {
            Log.formatSelector.debug("Download selected: itag=\(selected.itag ?? 0) codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)")
        }

        return selected
    }

    // Computes a sortable score for a format based on quality, channels, codec, bitrate
    private static func formatScore(_ format: Format) -> Int {
        let qualityScore = qualityRank(format.audioQuality) * 10_000

        let channelsScore = (format.audioChannels ?? 2) * 1_000
        let codecScore = scoreCodec(format.codec) * 100
        let bitrateScore = (format.bitrate ?? 0) / 1000  // normalize to kbps for readability

        let total = qualityScore + channelsScore + codecScore + bitrateScore
        Log.formatSelector.debug(
            "  Scoring itag=\(format.itag ?? 0): quality=\(qualityScore) channels=\(channelsScore) " +
                "codec=\(codecScore) bitrate=\(bitrateScore) total=\(total)"
        )

        return total
    }

    private static func scoreCodec(_ codec: String) -> Int {
        let lowercased = codec.lowercased()
        if lowercased.contains("opus") { return 2 }
        if lowercased.contains("mp4a") || lowercased.contains("aac") { return 1 }
        return 0
    }

    // MARK: - Video Format Selection

    /// Picks the best muxed video format (audio+video combined) for video playback.
    /// Prefers H.264 (avc/mp4) because the iOS Simulator cannot decode VP9/webm
    /// (VideoToolbox fails with err=-12847 and produces no frames). Real devices
    /// can decode VP9, but H.264 is the safe, universally-playable choice.
    ///
    /// A format only qualifies if it carries BOTH video dimensions AND an audio
    /// track (`audioChannels != nil`). DASH adaptive video entries (e.g. itag=137)
    /// have width/height but no audio, so playing one would yield "No video or
    /// audio streams selected" — they must be excluded.
    static func bestVideoFormat(from formats: [Format]) -> Format? {
        guard !formats.isEmpty else {
            Log.formatSelector.debug("No formats to select from (video)")
            return nil
        }

        // Require a genuinely combined stream: video dimensions AND audio.
        // (Static-image "videos" are video-only with no audio track, so they're
        // excluded here by `audioChannels != nil`. The 480p floor used for
        // *toggle visibility* in StreamResolver does not apply here — the only
        // universally-playable muxed stream on the simulator is 360p itag=18.)
        let muxedFormats = formats.filter {
            !$0.isAudioOnly
            && $0.width != nil && $0.height != nil
            && $0.audioChannels != nil
            && $0.url != nil
        }

        guard !muxedFormats.isEmpty else {
            Log.formatSelector.debug("No muxed (audio+video) formats found in \(formats.count) total formats")
            return nil
        }

        Log.formatSelector.debug("Selecting from \(muxedFormats.count) muxed video formats")

        // Split into H.264 (avc) and everything else
        let h264 = muxedFormats.filter { $0.codec.lowercased().contains("avc") || $0.mimeType?.lowercased().contains("mp4") == true }
        let pool = h264.isEmpty ? muxedFormats : h264
        if h264.isEmpty {
            Log.formatSelector.debug("No H.264 muxed format; falling back to any muxed format")
        } else {
            Log.formatSelector.debug("Using \(h264.count) H.264 muxed format(s)")
        }

        let selected = pool.max { a, b in
            videoFormatScore(a) < videoFormatScore(b)
        }

        if let selected {
            Log.formatSelector.debug(
                "Selected video: itag=\(selected.itag ?? 0) resolution=\(selected.width ?? 0)x\(selected.height ?? 0) " +
                    "codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)"
            )
        }

        return selected
    }

    /// Picks the best DASH video-only format (video track, no audio)
    static func bestVideoOnlyFormat(from formats: [Format]) -> Format? {
        guard !formats.isEmpty else {
            Log.formatSelector.debug("No formats to select from (video-only)")
            return nil
        }

        let videoOnlyFormats = formats.filter {
            !$0.isAudioOnly
            && $0.width != nil && $0.height != nil
            && $0.audioChannels == nil
            && $0.url != nil
        }

        guard !videoOnlyFormats.isEmpty else {
            Log.formatSelector.debug("No video-only formats found in \(formats.count) total formats")
            return nil
        }

        let h264 = videoOnlyFormats.filter { $0.codec.lowercased().contains("avc") || $0.mimeType?.lowercased().contains("mp4") == true }
        let poolBase = h264.isEmpty ? videoOnlyFormats : h264
        if h264.isEmpty {
            Log.formatSelector.debug("No H.264 video-only format; falling back to any video-only format")
        } else {
            Log.formatSelector.debug("Using \(h264.count) H.264 video-only format(s)")
        }

        let capped = poolBase.filter { ($0.height ?? 0) <= 720 }
        let pool = capped.isEmpty ? poolBase : capped
        if capped.isEmpty {
            Log.formatSelector.debug("No video-only format ≤720p; using higher-resolution pool")
        } else {
            Log.formatSelector.debug("Using \(capped.count) video-only format(s) ≤720p")
        }

        let selected = pool.max { a, b in
            videoFormatScore(a) < videoFormatScore(b)
        }

        if let selected {
            Log.formatSelector.debug(
                "Selected video-only: itag=\(selected.itag ?? 0)"
                + " resolution=\(selected.width ?? 0)x\(selected.height ?? 0)"
                + " codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)"
            )
        }

        return selected
    }

    private static func videoFormatScore(_ format: Format) -> Int {
        let widthScore = (format.width ?? 0) * 10
        let heightScore = (format.height ?? 0) * 10
        let bitrateScore = (format.bitrate ?? 0) / 1000
        return widthScore + heightScore + bitrateScore
    }
}
