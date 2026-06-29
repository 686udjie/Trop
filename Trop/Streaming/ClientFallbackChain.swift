//
//  ClientFallbackChain.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// Describes a client's behaviour in the fallback chain.
struct FallbackClient {
    let client: YouTubeClient
    /// Skip HEAD validation for this client (e.g. WEB_REMIX may be flaky but works)
    let skipValidation: Bool
}

/// Ordered list of clients to try when resolving a stream.
/// Each entry gets its own /player call; the first that returns a valid URL wins.
enum ClientFallbackChain {

    /// Preferred resolution order for music playback.
    static let preferred: [FallbackClient] = [
        FallbackClient(client: .webRemix, skipValidation: true),
        FallbackClient(client: .visionOS, skipValidation: false),
        FallbackClient(client: .androidVr1_43_32, skipValidation: false),
        FallbackClient(client: .androidVr1_61_48, skipValidation: false),
        FallbackClient(client: .iOS, skipValidation: false),
        FallbackClient(client: .mobile, skipValidation: false),
        FallbackClient(client: .web, skipValidation: true)
    ]
}
