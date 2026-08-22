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
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?
    let androidSdkVersion: String?
    let platform: String?
    let loginSupported: Bool
    let useSignatureTimestamp: Bool
    let useWebPoTokens: Bool
    let useMusicPlayerEndpoint: Bool
    let isEmbedded: Bool
    let includeUserAgentInContext: Bool
    let skipPlayerResponseValidation: Bool
    let clientScreen: String?
    let embedUrl: String?

    init(
        clientName: String,
        clientVersion: String,
        clientId: Int,
        userAgent: String,
        osName: String? = nil,
        osVersion: String? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        androidSdkVersion: String? = nil,
        platform: String? = nil,
        loginSupported: Bool = false,
        useSignatureTimestamp: Bool = false,
        useWebPoTokens: Bool = false,
        useMusicPlayerEndpoint: Bool = false,
        isEmbedded: Bool = false,
        includeUserAgentInContext: Bool = false,
        skipPlayerResponseValidation: Bool = false,
        clientScreen: String? = nil,
        embedUrl: String? = nil
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.clientId = clientId
        self.userAgent = userAgent
        self.osName = osName
        self.osVersion = osVersion
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.androidSdkVersion = androidSdkVersion
        self.platform = platform
        self.loginSupported = loginSupported
        self.useSignatureTimestamp = useSignatureTimestamp
        self.useWebPoTokens = useWebPoTokens
        self.useMusicPlayerEndpoint = useMusicPlayerEndpoint
        self.isEmbedded = isEmbedded
        self.includeUserAgentInContext = includeUserAgentInContext
        self.skipPlayerResponseValidation = skipPlayerResponseValidation
        self.clientScreen = clientScreen
        self.embedUrl = embedUrl
    }

    nonisolated static let userAgentWeb = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

    // Primary web client — used for most requests, needs cipher + PoToken
    nonisolated static let webRemix = YouTubeClient(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260707.12.00",
        clientId: 67,
        userAgent: userAgentWeb,
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    // yt-dlp's default Android VR profile — stable direct URLs
    nonisolated static let androidVr1_65_10 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.65.10",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        osName: "Android",
        osVersion: "12L",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32",
        useMusicPlayerEndpoint: true,
        includeUserAgentInContext: true
    )

    nonisolated static let androidVr1_43_32 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3;" +
            " Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32",
        useMusicPlayerEndpoint: true,
        includeUserAgentInContext: true
    )

    // Newer Android VR version — direct URLs
    nonisolated static let androidVr1_61_48 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3;" +
            " Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32",
        useMusicPlayerEndpoint: true,
        includeUserAgentInContext: true
    )

    nonisolated static let tvHtml5 = YouTubeClient(
        clientName: "TVHTML5",
        clientVersion: "7.20260707.07.00",
        clientId: 7,
        userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko)," +
            " Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)",
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true,
        includeUserAgentInContext: true
    )

    nonisolated static let iOS = YouTubeClient(
        clientName: "IOS",
        clientVersion: "21.26.4",
        clientId: 5,
        userAgent: "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        osName: "iPhone",
        osVersion: "18.3.2.22D82",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2",
        includeUserAgentInContext: true
    )

    nonisolated static let visionOS = YouTubeClient(
        clientName: "VISIONOS",
        clientVersion: "0.1",
        clientId: 101,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
        osName: "VISION_OS",
        osVersion: "1.3",
        deviceMake: "Apple",
        deviceModel: "RealityDevice14,1",
        platform: "MOBILE",
        useMusicPlayerEndpoint: true,
        skipPlayerResponseValidation: true
    )

    // Mobile Android client — needs platform attestation, late fallback only
    nonisolated static let mobile = YouTubeClient(
        clientName: "ANDROID",
        clientVersion: "21.26.364",
        clientId: 3,
        userAgent: "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
        osName: "Android",
        osVersion: "11",
        androidSdkVersion: "30",
        includeUserAgentInContext: true
    )

    /// Embedded player that can bypass age-restriction.
    /// Does not require login for age-restricted content.
    nonisolated static let tvHtml5SimplyEmbedded = YouTubeClient(
        clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        clientVersion: "2.0",
        clientId: 85,
        userAgent: tvHtml5.userAgent,
        useSignatureTimestamp: true,
        useWebPoTokens: true,
        isEmbedded: true,
        embedUrl: "https://www.reddit.com/"
    )
}
