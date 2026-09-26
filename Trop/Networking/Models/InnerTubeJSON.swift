//
//  InnerTubeJSON.swift
//  Trop
//
// Created by 686udjie on 13/09/2026.
//

import Foundation

/// Shared accessors for InnerTube browse JSON shapes. Consolidates the
/// copy-pasted `extractRunsText` / `extractThumbnail*` / `extractRawRuns`
/// helpers previously duplicated across InnerTube, MutationService,
/// PersonalizationService, YTItem, HomePageParser, LibraryBrowseParser and
/// DetailParser. Lookup paths are preserved exactly — only the leaf
/// extraction is unified.
enum InnerTubeJSON {
    /// First run's text from `{runs: [{text}]}`. Tolerant: joins split runs,
    /// falls back to `simpleText`/`text` (see `InnerTubeDecode`).
    static func runsText(_ dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        if let runs = dict["runs"] as? [[String: Any]], !runs.isEmpty {
            let texts = runs.compactMap { $0["text"] as? String }
            let joined = texts.joined()
            if !joined.isEmpty { return joined }
        }
        return InnerTubeDecode.runsTextTolerant(dict)
    }

    /// All non-blank run texts, dropping `" • "` separators.
    static func runsTexts(_ dict: [String: Any]?) -> [String] {
        guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
        return runs.compactMap { $0["text"] as? String }
            .filter { $0 != " • " && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Raw runs array (empty when absent).
    static func rawRuns(_ dict: [String: Any]?) -> [[String: Any]] {
        guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
        return runs
    }

    /// Last URL of a `thumbnails` array (largest variant).
    static func lastThumbnailURL(_ thumbnails: [[String: Any]]?) -> String? {
        guard let last = thumbnails?.last,
              let url = last["url"] as? String else { return nil }
        return url
    }

    /// Last URL of `{thumbnail: {thumbnails: [...]}}`.
    static func nestedThumbnailURL(_ dict: [String: Any]?) -> String? {
        lastThumbnailURL((dict?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])
    }

    /// Largest thumbnail URL across InnerTube thumbnail formats:
    /// `musicThumbnailRenderer` first, then plain `thumbnails`, then
    /// `croppedSquareThumbnail`. Tolerant to unknown envelopes (nil, logged).
    static func musicThumbnailURL(_ dict: [String: Any]) -> String? {
        if let url = InnerTubeDecode.thumbnailURLTolerant(dict) {
            return url
        }
        InnerTubeDecode.warnOnce("musicThumbnailURL: unknown thumbnail envelope keys=\(dict.keys.sorted())")
        return nil
    }
}
