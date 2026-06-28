//
//  YouTubeClient.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Defines client identities used in InnerTube API requests
struct YouTubeClient: Codable {
    let clientName: String
    let clientVersion: String
    let clientId: Int
    let userAgent: String
    let useSignatureTimestamp: Bool
    let useWebPoTokens: Bool

    // Primary web client — used for most requests, needs cipher + PoToken
    nonisolated static let webRemix = YouTubeClient(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260213.01.00",
        clientId: 67,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    nonisolated static let androidVr1_43_32 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: 67,
        userAgent: "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36",
        useSignatureTimestamp: false,
        useWebPoTokens: false
    )

    // Newer Android VR version — direct URLs
    nonisolated static let androidVr1_61_48 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: 67,
        userAgent: "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36",
        useSignatureTimestamp: false,
        useWebPoTokens: false
    )

    nonisolated static let iOS = YouTubeClient(
        clientName: "IOS",
        clientVersion: "20.02.3",
        clientId: 5,
        userAgent: "com.google.ios.youtube/20.02.3 (iPhone; iOS 18.0; en_US)",
        useSignatureTimestamp: false,
        useWebPoTokens: false
    )

    nonisolated static let visionOS = YouTubeClient(
        clientName: "VISIONOS",
        clientVersion: "1.01.01",
        clientId: 74,
        userAgent: "Vision/1.0 CFNetwork/ Darwin/",
        useSignatureTimestamp: false,
        useWebPoTokens: false
    )

    // Mobile web client
    nonisolated static let mobile = YouTubeClient(
        clientName: "MOBILE",
        clientVersion: "20.02.3",
        clientId: 2,
        userAgent: "com.google.android.apps.youtube.music/20.02.3 (Linux; Android 14)",
        useSignatureTimestamp: false,
        useWebPoTokens: false
    )

    nonisolated static let web = YouTubeClient(
        clientName: "WEB",
        clientVersion: "2.20260213.01.00",
        clientId: 1,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )
}
