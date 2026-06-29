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

    /// Fallback chain with WEB_REMIX as LAST RESORT (requires cipher + PoToken).
    /// Clients returning direct URLs (no cipher) are tried first.
    static let preferred: [FallbackClient] = [
        FallbackClient(client: .visionOS, skipValidation: false),     // direct URLs
        FallbackClient(client: .androidVr1_61_48, skipValidation: false), // direct URLs
        FallbackClient(client: .androidVr1_43_32, skipValidation: false), // direct URLs
        FallbackClient(client: .iOS, skipValidation: false),          // direct URLs
        FallbackClient(client: .mobile, skipValidation: false),       // signatureTimestamp only
        FallbackClient(client: .web, skipValidation: true),           // cipher + PoToken
        FallbackClient(client: .webRemix, skipValidation: true),      // cipher + PoToken (last resort)
    ]
}
