//
//  SAPISIDAuth.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation
import CommonCrypto

// Generates the SAPISIDHASH Authorization header value for signed-in requests
enum SAPISIDAuth {
    // Produces "SAPISIDHASH <timestamp>_<sha1>" from the SAPISID cookie value
    static func authorizationHeader(sapisid: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let hash = sha1("\(timestamp) \(sapisid) https://music.youtube.com")
        return "SAPISIDHASH \(timestamp)_\(hash)"
    }

    private static func sha1(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
