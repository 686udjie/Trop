//
//  CipherExecutor.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import JavaScriptCore

/// Executes cipher (signature deobfuscation) and n-transform functions against
/// JavaScriptCore using function bodies extracted from YouTube's player.js.
actor CipherExecutor {
    static let shared = CipherExecutor()

    private init() {}

    func resolveCipherURL(cipherText: String,
                          playerJs: String,
                          playerHash: String?) async throws -> String
    {
        try await CipherWebView.shared.load()
        return try await CipherWebView.shared.resolveCipherURL(cipherText: cipherText)
    }

    func getSignatureTimestamp() async throws -> Int {
        try await PlayerJsFetcher.shared.getSignatureTimestamp()
    }
}
