//
//  ClientFallbackChain.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

// Wrapper for a YouTubeClient with validation skip flag
struct FallbackClient {
    let client: YouTubeClient
    let skipValidation: Bool
}

// Ordered list of clients to try when resolving a stream.
// Each entry gets its own /player call; the first that returns a valid URL wins.
enum ClientFallbackChain {
    /// Base chain — fast direct-URL clients first, token-backed web clients last.
    /// Mirrors innertubex's client guidance as of July 2026.
    private static let base: [FallbackClient] = [
        FallbackClient(client: .visionOS, skipValidation: false),
        FallbackClient(client: .androidVr1_65_10, skipValidation: false),
        FallbackClient(client: .androidVr1_61_48, skipValidation: false),
        FallbackClient(client: .androidVr1_43_32, skipValidation: false),
        FallbackClient(client: .tvHtml5SimplyEmbedded, skipValidation: false),
        FallbackClient(client: .iOS, skipValidation: true),
        FallbackClient(client: .tvHtml5, skipValidation: false),
        FallbackClient(client: .mobile, skipValidation: false),
        FallbackClient(client: .webRemix, skipValidation: true)
    ]

    /// Fallback chain for playback.
    static var preferred: [FallbackClient] { base }

    /// Download resolve order — same proven direct-URL clients as playback.
    /// HEAD validation stays on for early clients so we don't download dead URLs;
    /// iOS/webRemix still skip HEAD (they often break HEAD while GET works).
    static var forDownload: [FallbackClient] { base }
}
