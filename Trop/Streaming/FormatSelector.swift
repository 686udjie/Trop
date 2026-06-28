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

    // Picks the optimal audio format for playback
    static func bestAudioFormat(from formats: [Format]) -> Format? {
        // Filter to audio-only formats (no video dimensions)
        guard !formats.isEmpty else {
            print("[FormatSelector] No formats to select from")
            return nil
        }

        let audioFormats = formats.filter { $0.isAudioOnly }

        guard !audioFormats.isEmpty else {
            print("[FormatSelector] No audio-only formats found in \(formats.count) total formats")
            return nil
        }

        print("[FormatSelector] Selecting from \(audioFormats.count) audio-only formats")

        let selected = audioFormats.max { a, b in
            formatScore(a) < formatScore(b)
        }

        if let selected {
            print("[FormatSelector] Selected: itag=\(selected.itag ?? 0)"
                + " quality=\(selected.audioQuality ?? "?")"
                + " channels=\(selected.audioChannels ?? 0)"
                + " codec=\(selected.codec)"
                + " bitrate=\(selected.bitrate ?? 0)")
        } else {
            print("[FormatSelector] No format could be selected")
        }

        return selected
    }

    // Computes a sortable score for a format based on quality, channels, codec, bitrate
    private static func formatScore(_ format: Format) -> Int {
        let qualityScore: Int = {
            switch format.audioQuality {
            case "AUDIO_QUALITY_HIGH":   30_000
            case "AUDIO_QUALITY_MEDIUM": 20_000
            case "AUDIO_QUALITY_LOW":    10_000
            default:                          0
            }
        }()

        let channelsScore = (format.audioChannels ?? 2) * 1_000
        let codecScore = scoreCodec(format.codec) * 100
        let bitrateScore = (format.bitrate ?? 0) / 1000  // normalize to kbps for readability

        let total = qualityScore + channelsScore + codecScore + bitrateScore
        print("[FormatSelector]   Scoring itag=\(format.itag ?? 0):"
            + " quality=\(qualityScore)"
            + " channels=\(channelsScore)"
            + " codec=\(codecScore)"
            + " bitrate=\(bitrateScore)"
            + " total=\(total)")

        return total
    }

    private static func scoreCodec(_ codec: String) -> Int {
        let lowercased = codec.lowercased()
        if lowercased.contains("opus") { return 2 }
        if lowercased.contains("mp4a") || lowercased.contains("aac") { return 1 }
        return 0
    }
}
