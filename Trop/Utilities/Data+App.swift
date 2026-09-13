//
//  Data+App.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import CryptoKit
import Foundation

extension Data {
    /// Base64URL without padding. Consolidates the duplicates in
    /// DiscordAuth and DiscordOAuthWebView.
    var base64URLEncodedNoPadding: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// SHA-256 digest, Base64URL-encoded without padding.
    var sha256Base64URLEncoded: String {
        let hash = SHA256.hash(data: self)
        return Data(hash).base64URLEncodedNoPadding
    }
}
