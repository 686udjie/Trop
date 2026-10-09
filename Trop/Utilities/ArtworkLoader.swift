//
//  ArtworkLoader.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation
import Nuke
import UIKit

/// Shared Nuke access for imperative (non-view) artwork loads. Consolidates
/// the copy-pasted cache-check-then-fetch pairs in NowPlaying,
/// MiniPlayerBarView, DownloadManager and ArtistDetailView.
///
/// Note: `image(for:)` already consults the memory + disk caches before
/// hitting the network, so callers must not pre-check the cache themselves.
enum ArtworkLoader {
    /// Cached image without hitting the network (nil on cache miss).
    static func cachedImage(for url: URL) -> UIImage? {
        ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: url), caches: .all)?.image
    }

    /// Cached image when present, otherwise fetches (and caches) it.
    static func image(for url: URL) async throws -> UIImage {
        try await ImagePipeline.shared.image(for: url)
    }

    /// Best-effort cache warm, never throws.
    static func warm(_ url: URL) {
        Task { _ = try? await ImagePipeline.shared.image(for: url) }
    }
}

/// Artwork URL builders. Consolidates the copy-pasted `hqdefault.jpg`
/// fallback literal and the `w/h` size rewrite.
enum ArtworkURLs {
    /// i.ytimg fallback artwork for a video id.
    static func fallback(for videoId: String) -> String {
        "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    /// Rewrites a `w<N>-h<N>` thumbnail URL to the requested square size.
    static func sized(_ url: String?, width: Int, height: Int) -> String? {
        url?.replacingOccurrences(
            of: #"w\d+-h\d+"#,
            with: "w\(width)-h\(height)",
            options: .regularExpression
        )
    }

    static func highRes(_ url: String?, size: Int = 1024) -> String? {
        guard var url = url, !url.isEmpty else { return nil }
        url = url.replacingOccurrences(of: "(?<=[sh]\\d+)-c", with: "", options: .regularExpression)
        guard url.contains("googleusercontent.com") || url.contains("ggpht.com") else { return url }
        if url.range(of: #"w\d+-h\d+"#, options: .regularExpression) != nil {
            url = url.replacingOccurrences(
                of: #"w\d+-h\d+"#,
                with: "w\(size)-h\(size)",
                options: .regularExpression
            )
        } else if let base = url.split(separator: "=").first {
            url = String(base) + "=w\(size)-h\(size)"
        }
        return url
    }

    static func maxResVariant(_ url: String?) -> String? {
        guard let url, url.contains("i.ytimg.com"), url.hasSuffix("/hqdefault.jpg") else { return nil }
        return url.replacingOccurrences(of: "/hqdefault.jpg", with: "/maxresdefault.jpg")
    }
}
