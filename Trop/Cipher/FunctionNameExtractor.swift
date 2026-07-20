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
        let sigBody = extractCipherFunctionHeuristic(js)
        let nBody = extractNFunctionHeuristic(js)
        let nClass = extractNClassHeuristic(js)
        return ExtractedFunctions(
            sigJs: sigBody.map { wrapSigFunction($0) } ?? "",
            nJs: nBody.map { wrapNFunction($0) },
            nClass: nClass
        )
    }

    /// Extract the signature deobfuscation function body using heuristics.
    /// Scans all function definitions for the signature cipher patterns:
    /// `.split("")` + `.join("")` — the hallmarks of the deobfuscation algorithm.
    private func extractCipherFunctionHeuristic(_ js: String) -> String? {
        scanFunctions(in: js, bodyValidator: hasCipherPatterns, maxBodyLength: 3000)
    }

    /// Extract n-transform function body using heuristics.
    /// Scans all function definitions for `charCodeAt` + `fromCharCode` usage.
    private func extractNFunctionHeuristic(_ js: String) -> String? {
        scanFunctions(in: js, bodyValidator: hasNTransformPatterns, maxBodyLength: 3000)
    }

    /// Walk every function definition in `js`, extract its body, and return the
    /// first one where `bodyValidator` returns true.
    private func scanFunctions(
        in js: String,
        bodyValidator: (String) -> Bool,
        maxBodyLength: Int
    ) -> String? {
        let nsJs = js as NSString
        let fullRange = NSRange(location: 0, length: nsJs.length)

        guard let funcRegex = try? NSRegularExpression(
            pattern: #"\bfunction\s*\([^)]*\)\s*\{"#,
            options: []
        ) else { return nil }

        let matches = funcRegex.matches(in: js, range: fullRange)
        for match in matches {
            let start = match.range.location
            guard let end = findMatchingBrace(js, from: start) else { continue }
            let bodyRange = NSRange(location: start, length: end - start + 1)
            guard bodyRange.length < maxBodyLength else { continue }

            let body = nsJs.substring(with: bodyRange)
            if bodyValidator(body) {
                return body
            }
        }

        // Try alternate: method-assignment form (e.g. `x.y = function(...){...}`)
        guard let methodRegex = try? NSRegularExpression(
            pattern: #"\w+\s*=\s*function\s*\([^)]*\)\s*\{"#,
            options: []
        ) else { return nil }

        let methodMatches = methodRegex.matches(in: js, range: fullRange)
        for match in methodMatches {
            let start = match.range.location
            guard let end = findMatchingBrace(js, from: start) else { continue }
            let bodyRange = NSRange(location: start, length: end - start + 1)
            guard bodyRange.length < maxBodyLength else { continue }

            let body = nsJs.substring(with: bodyRange)
            if bodyValidator(body),
               let funcRange = body.range(of: "function") {
                let funcStr = String(body[funcRange.lowerBound...])
                if bodyValidator(funcStr) {
                    return funcStr
                }
            }
        }

        return nil
    }

    /// A cipher (signature deobfuscation) function must contain both
    /// `.split("")` and `.join("")` (with either quote style).
    private func hasCipherPatterns(_ body: String) -> Bool {
        let hasSplit = body.contains(#".split(""#) || body.contains(".split('')")
        let hasJoin = body.contains(#".join(""#) || body.contains(".join('')")
        return hasSplit && hasJoin
    }

    /// An n-transform function must invoke `charCodeAt` and `fromCharCode`.
    private func hasNTransformPatterns(_ body: String) -> Bool {
        body.contains("charCodeAt") && body.contains("fromCharCode")
    }

    /// Extract the URL builder class name (nClass) from player.js heuristically.
    /// Looks for `(new g.<class>(url, true)).get("n")` or similar patterns.
    private func extractNClassHeuristic(_ js: String) -> String? {
        let patterns = [
            #"\(?new\s+g\.(\w+)\([^,]+,\s*(?:!0|true)\)\)?\s*\.[\w$]+\(\s*['""]n['""]\s*\)"#,
            #"new\s+g\.(\w+)\([^,]+,\s*!0\)"#,
        ]

        let nsJs = js as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: js, range: NSRange(location: 0, length: nsJs.length))
            guard let match = matches.first else { continue }
            return nsJs.substring(with: match.range(at: 1))
        }
        return nil
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
