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
    /// First run's text from `{runs: [{text}]}`.
    static func runsText(_ dict: [String: Any]?) -> String? {
        guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
        return first["text"] as? String
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
    /// `croppedSquareThumbnail`.
    static func musicThumbnailURL(_ dict: [String: Any]) -> String? {
        if let thumbnail = dict["thumbnail"] as? [String: Any],
           let musicThumb = thumbnail["musicThumbnailRenderer"] as? [String: Any] {
            if let url = nestedThumbnailURL(musicThumb) {
                return url
            }
        }
        if let url = nestedThumbnailURL(dict) {
            return url
        }
        if let cropped = dict["croppedSquareThumbnail"] as? [String: Any] {
            return lastThumbnailURL(cropped["thumbnails"] as? [[String: Any]])
        }
        return nil
    }
}
