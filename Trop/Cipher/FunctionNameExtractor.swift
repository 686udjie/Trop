//
//  FunctionNameExtractor.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// Extracts cipher (signature deobfuscation) and n-transform functions
/// from YouTube's player.js using config lookups and regex heuristics.
actor FunctionNameExtractor {
    static let shared = FunctionNameExtractor()

    /// Result of extracting cipher functions from player.js
    struct ExtractedFunctions {
        /// JavaScript signature deobfuscation function body (as a callable expression)
        var sigJs: String
        /// JavaScript n-transform function body (as a callable expression)
        var nJs: String?
        /// URL builder class name on `window.g` used for n-param transform
        var nClass: String?
    }

    private init() {}

    /// Extract cipher functions from player.js, optionally using a known hash for config lookup
    func extract(from playerJs: String, playerHash: String? = nil) async throws -> ExtractedFunctions {
        // Try config store first
        if let hash = playerHash,
           let config = await PlayerConfigStore.shared.config(for: hash) {
            // If we already have the function bodies, use them
            if let sigBody = config.sigFunction.body,
               let nBody = config.nFunction.body {
                return ExtractedFunctions(
                    sigJs: wrapSigFunction(sigBody, hash: hash),
                    nJs: wrapNFunction(nBody)
                )
            }
            // If we have extraction patterns, try those
            if let sigPattern = config.sigFunction.extractPattern {
                if let sigBody = extractByPattern(sigPattern, from: playerJs) {
                    let nBody: String?
                    if let nPattern = config.nFunction.extractPattern {
                        nBody = extractByPattern(nPattern, from: playerJs)
                    } else {
                        nBody = extractNFunctionHeuristic(playerJs)
                    }
                    return ExtractedFunctions(
                        sigJs: wrapSigFunction(sigBody, hash: hash),
                        nJs: nBody.map { wrapNFunction($0) }
                    )
                }
            }
        }

        // Fallback to heuristic extraction
        return try extractHeuristic(from: playerJs)
    }

    /// Extracts the signature timestamp from player.js
    func extractSignatureTimestamp(from playerJs: String) -> Int? {
        let patterns = [
            #/signatureTimestamp["':\s]+(\d+)/#,
            #/signatureTimestamp["']\s*:\s*(\d+)/#
        ]
        for pattern in patterns {
            if let match = playerJs.firstMatch(of: pattern) {
                return Int(match.1)
            }
        }
        return nil
    }

    // MARK: - Heuristic Extraction

    private func extractHeuristic(from js: String) throws -> ExtractedFunctions {
        guard let sigBody = extractCipherFunctionHeuristic(js) else {
            throw CipherError.functionNotFound("cipher function")
        }
        let nBody = extractNFunctionHeuristic(js)
        let nClass = extractNClassHeuristic(js)
        return ExtractedFunctions(
            sigJs: wrapSigFunction(sigBody),
            nJs: nBody.map { wrapNFunction($0) },
            nClass: nClass
        )
    }

    /// Extract the signature deobfuscation function body using heuristics.
    /// The function is identified by: `a=a.split("")` and `a.join("")` patterns.
    private func extractCipherFunctionHeuristic(_ js: String) -> String? {
        // Find the start of a function that splits a string param
        // Pattern: function(X){X=X.split("")  (where X is a single lowercase letter)
        guard let funcStartPattern = try? NSRegularExpression(
            pattern: #"function\s*\(([a-z])\)\s*\{\1\s*=\s*\1\s*\.\s*split\s*\(\s*['"]{2}\s*\)"#,
            options: []
        ) else { return nil }

        let nsJs = js as NSString
        let matches = funcStartPattern.matches(in: js, range: NSRange(location: 0, length: nsJs.length))

        for match in matches {
            let start = match.range.location
            // Find the matching closing brace
            guard let end = findMatchingBrace(js, from: start) else { continue }
            let range = NSRange(location: start, length: end - start + 1)
            let functionBody = nsJs.substring(with: range)

            // Verify it contains join("") and is a reasonable size
            if functionBody.contains("join("), functionBody.count < 2000 {
                return functionBody
            }
        }
        return nil
    }

    /// Extract n-transform function body using heuristics.
    /// Looks for functions containing `charCodeAt` and `fromCharCode`.
    private func extractNFunctionHeuristic(_ js: String) -> String? {
        // Look for function that takes a single param and uses charCodeAt
        guard let pattern = try? NSRegularExpression(
            pattern: #"function\s*\(([a-z])\)\s*\{(?:[^}]*\1\.charCodeAt[^}]*)"#,
            options: []
        ) else { return nil }

        let nsJs = js as NSString
        let matches = pattern.matches(in: js, range: NSRange(location: 0, length: nsJs.length))

        for match in matches {
            let start = match.range.location
            guard let end = findMatchingBrace(js, from: start) else { continue }
            let range = NSRange(location: start, length: end - start + 1)
            let functionBody = nsJs.substring(with: range)

            if functionBody.contains("fromCharCode"), functionBody.count < 2000 {
                return functionBody
            }
        }
        return nil
    }

    /// Extract the URL builder class name (nClass) from player.js heuristically.
    /// Looks for `new g.<class>(url, true).<method>("n")` pattern.
    private func extractNClassHeuristic(_ js: String) -> String? {
        guard let pattern = try? NSRegularExpression(
            pattern: #"new\s+g\.(\w+)\([^,]+,\s*(?:!0|true)\)\s*\.[\w$]+\(\s*['"]n['"]\s*\)"#,
            options: []
        ) else { return nil }

        let nsJs = js as NSString
        let matches = pattern.matches(in: js, range: NSRange(location: 0, length: nsJs.length))
        guard let match = matches.first else { return nil }
        return nsJs.substring(with: match.range(at: 1))
    }

    // MARK: - Brace Matching

    /// Find the position of the matching closing brace, starting from `from` which
    /// is assumed to be at or before the opening `{`.
    private func findMatchingBrace(_ str: String, from start: Int) -> Int? {
        let index = str.index(str.startIndex, offsetBy: start)
        // Find the first `{` from `start`
        guard let openBrace = str[index...].firstIndex(of: "{") else { return nil }
        let openOffset = str.distance(from: str.startIndex, to: openBrace)

        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for offset in openOffset..<str.count {
            let char = str[str.index(str.startIndex, offsetBy: offset)]

            if escaped {
                escaped = false
                continue
            }

            if char == "\\" { escaped = true; continue }

            if char == "'" && !inDoubleQuote { inSingleQuote.toggle(); continue }
            if char == "\"" && !inSingleQuote { inDoubleQuote.toggle(); continue }

            if !inSingleQuote && !inDoubleQuote {
                if char == "{" { depth += 1 } else if char == "}" {
                    depth -= 1
                    if depth == 0 { return offset }
                }
            }
        }
        return nil
    }

    // MARK: - Pattern Extraction

    /// Extract a function body using a regex pattern
    private func extractByPattern(_ pattern: String, from js: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsJs = js as NSString
        guard let match = regex.firstMatch(in: js, range: NSRange(location: 0, length: nsJs.length)) else {
            return nil
        }
        let start = match.range.location
        guard let end = findMatchingBrace(js, from: start) else { return nil }
        return nsJs.substring(with: NSRange(location: start, length: end - start + 1))
    }

    // MARK: - Wrapping

    /// Wrap the extracted cipher function body as a callable JS expression.
    /// The function takes a signature string and returns the deobfuscated signature.
    private func wrapSigFunction(_ body: String, hash: String? = nil) -> String {
        "(\(body))"
    }

    /// Wrap the extracted n-transform function body as a callable JS expression.
    private func wrapNFunction(_ body: String) -> String {
        "(\(body))"
    }
}
