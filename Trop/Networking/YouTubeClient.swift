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
    let loginSupported: Bool
    let useSignatureTimestamp: Bool
    let useWebPoTokens: Bool

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
        loginSupported: Bool = false,
        useSignatureTimestamp: Bool = false,
        useWebPoTokens: Bool = false
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
        self.loginSupported = loginSupported
        self.useSignatureTimestamp = useSignatureTimestamp
        self.useWebPoTokens = useWebPoTokens
    }

    // Primary web client — used for most requests, needs cipher + PoToken
    nonisolated static let webRemix = YouTubeClient(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260213.01.00",
        clientId: 67,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    nonisolated static let androidVr1_43_32 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    // Newer Android VR version — direct URLs
    nonisolated static let androidVr1_61_48 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    nonisolated static let iOS = YouTubeClient(
        clientName: "IOS",
        clientVersion: "21.03.1",
        clientId: 5,
        userAgent: "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
        osVersion: "18.2.22C152"
    )

    nonisolated static let visionOS = YouTubeClient(
        clientName: "VISIONOS",
        clientVersion: "0.1",
        clientId: 101,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        osName: "visionOS",
        osVersion: "1.3.21O771",
        deviceMake: "Apple",
        deviceModel: "RealityDevice14,1"
    )

    // Mobile Android client
    nonisolated static let mobile = YouTubeClient(
        clientName: "ANDROID",
        clientVersion: "21.03.38",
        clientId: 3,
        userAgent: "com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip",
        loginSupported: true,
        useSignatureTimestamp: true
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
