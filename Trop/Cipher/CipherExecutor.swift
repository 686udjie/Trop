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

    /// Deobfuscates a stream URL signature given the obfuscated signature string
    func deobfuscateSignature(_ obfuscated: String,
                              playerJs: String,
                              playerHash: String?) async throws -> String
    {
        let extracted = try await FunctionNameExtractor.shared.extract(
            from: playerJs, playerHash: playerHash
        )
        let script = "\(extracted.sigJs)(\"\(obfuscated)\")"
        return try evaluate(script)
    }

    /// Transforms the `n` parameter from a stream URL using the n-transform function
    func transformN(_ n: String,
                    playerJs: String,
                    playerHash: String?) async throws -> String
    {
        let extracted = try await FunctionNameExtractor.shared.extract(
            from: playerJs, playerHash: playerHash
        )
        guard let nJs = extracted.nJs else {
            throw CipherError.functionNotFound("n-transform")
        }
        let script = "\(nJs)(\"\(n)\")"
        return try evaluate(script)
    }

    /// Deobfuscates a full cipher block (signatureCipher/ cipher) into a playable URL
    func resolveCipherURL(cipherText: String,
                          playerJs: String,
                          playerHash: String?) async throws -> String
    {
        let params = parseQueryString(cipherText)
        guard let urlParam = params["url"]?.removingPercentEncoding else {
            throw CipherError.invalidResponse("No url in cipher text")
        }
        let sigParam = params["s"]
        let spParam = params["sp"] ?? "signature"
        let nParam = params["n"]

        var url = urlParam

        // Deobfuscate signature
        if let sig = sigParam {
            let deobfuscated = try await deobfuscateSignature(sig, playerJs: playerJs, playerHash: playerHash)
            let sigSeparator = url.contains("?") ? "&" : "?"
            url += "\(sigSeparator)\(spParam)=\(deobfuscated)"
        }

        // Transform n parameter
        if let n = nParam {
            let transformed = try await transformN(n, playerJs: playerJs, playerHash: playerHash)
            url = url.replacingOccurrences(of: "n=\(n)", with: "n=\(transformed)")
        }

        return url
    }

    /// Manually parse a query string into key-value pairs
    private func parseQueryString(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1])
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Private

    /// Evaluates a JS expression in a fresh JSContext and returns the string result.
    /// Each call creates a new context to avoid threading issues.
    private func evaluate(_ script: String) throws -> String {
        guard let context = JSContext() else {
            throw CipherError.jsExecutionFailed("Cannot create JSContext")
        }
        // Suppress JS exceptions from polluting logs
        context.exceptionHandler = { _, exception in
            print("[Cipher] JS exception: \(exception?.toString() ?? "unknown")")
        }

        guard let result = context.evaluateScript(script) else {
            throw CipherError.jsExecutionFailed("Script returned nil")
        }
        guard !result.isUndefined else {
            throw CipherError.jsExecutionFailed("Script returned undefined")
        }
        guard let string = result.toString() else {
            throw CipherError.jsExecutionFailed("Cannot convert result to string")
        }
        return string
    }
}
