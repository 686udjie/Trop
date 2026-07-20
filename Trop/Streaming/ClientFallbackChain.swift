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

    /// Fallback chain — direct-URL clients first, cipher clients last.
    static let preferred: [FallbackClient] = [
        FallbackClient(client: .visionOS, skipValidation: false),
        FallbackClient(client: .androidVr1_61_48, skipValidation: false),
        FallbackClient(client: .androidVr1_43_32, skipValidation: false),
        FallbackClient(client: .tvHtml5SimplyEmbedded, skipValidation: false),
        FallbackClient(client: .iOS, skipValidation: true),
        FallbackClient(client: .mobile, skipValidation: false),
        FallbackClient(client: .web, skipValidation: true),
        FallbackClient(client: .webRemix, skipValidation: true),
    ]
}
