//
//  DiscordSuperProperties.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import UIKit

enum DiscordSuperProperties {
    static let userAgent = DiscordDefaults.userAgent

    private static var cachedBase64: String?
    private static var cachedJson: [String: Any]?

    static var base64: String {
        if let c = cachedBase64 { return c }
        let json = superProperties
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else { return "" }
        // Standard Base64 NO_WRAP
        let encoded = data.base64EncodedString()
        cachedBase64 = encoded
        return encoded
    }

    static var superProperties: [String: Any] {
        if let c = cachedJson { return c }
        let dict = build()
        cachedJson = dict
        return dict
    }

    private static func build() -> [String: Any] {
        let vendorId = DiscordTokenStore.shared.getDeviceVendorId() ?? UUID().uuidString
        let clientUuid = DiscordTokenStore.shared.getClientUuid() ?? UUID().uuidString
        let device = UIDevice.current.model // e.g. "iPhone"
        let systemVersion = UIDevice.current.systemVersion
        let parts = Locale.current.identifier // e.g. en_US
        return [
            "os": "iOS",
            "browser": "Discord iOS",
            "device": device,
            "system_locale": parts,
            "client_version": DiscordDefaults.clientVersion,
            "release_channel": DiscordDefaults.releaseChannel,
            "device_vendor_id": vendorId,
            "client_uuid": clientUuid,
            "client_launch_id": UUID().uuidString,
            "os_version": systemVersion,
            "os_sdk_version": UIDevice.current.systemVersion,
            "client_build_number": DiscordDefaults.clientBuildNumber,
            "client_event_source": NSNull(),
            "design_id": 0
        ]
    }

    static func reset() {
        cachedBase64 = nil
        cachedJson = nil
    }
}
