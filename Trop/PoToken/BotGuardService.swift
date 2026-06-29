//
//  BotGuardService.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

actor BotGuardService {
    static let shared = BotGuardService()

    private let apiKey = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"
    private let requestKey = "O43z0dpjhgX20SCx4KAo"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.3"
    private let session = URLSession(configuration: .default)

    private init() {}

    func createChallenge() async throws -> BotGuardChallenge {
        let url = URL(string: "https://www.youtube.com/api/jnn/v1/Create")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        // Body: JSON array with requestKey
        req.httpBody = try JSONSerialization.data(withJSONObject: [requestKey])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw BotGuardError.createFailed
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw BotGuardError.invalidResponse
        }

        return try parseChallenge(body)
    }

    func generateIT(botguardResponse: String) async throws -> (integrityToken: String, expiresIn: Int) {
        let url = URL(string: "https://www.youtube.com/api/jnn/v1/GenerateIT")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        // Body: JSON array [requestKey, botguardResponse]
        req.httpBody = try JSONSerialization.data(withJSONObject: [requestKey, botguardResponse])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw BotGuardError.generateITFailed
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw BotGuardError.invalidResponse
        }

        return try parseIntegrityToken(body)
    }

    // MARK: - Challenge Parsing

    /// Parses the raw Create response into challenge data for the WebView.
    /// Response format: [scrambled_or_descrambled, ...]
    /// If element [1] is a string, it's scrambled; descramble by base64 decoding + adding 97 to each byte.
    private func parseChallenge(_ raw: String) throws -> BotGuardChallenge {
        guard let data = raw.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1 else {
            throw BotGuardError.invalidResponse
        }

        // The challenge data is either at [0] or descrambled from [1]
        let challengeArray: [Any]
        if json.count > 1, let scrambled = json[1] as? String {
            let descrambled = descramble(scrambled)
            guard let d = descrambled.data(using: .utf8),
                  let arr = try JSONSerialization.jsonObject(with: d) as? [Any] else {
                throw BotGuardError.descrambleFailed
            }
            challengeArray = arr
        } else if let arr = json[0] as? [Any] {
            challengeArray = arr
        } else {
            throw BotGuardError.invalidResponse
        }

        guard challengeArray.count >= 8,
              let messageId = challengeArray[0] as? String,
              let interpreterHash = challengeArray[3] as? String,
              let program = challengeArray[4] as? String,
              let globalName = challengeArray[5] as? String else {
            throw BotGuardError.invalidResponse
        }

        // Extract interpreter JS from element [1] (may be nested)
        var interpreterJs: String?
        if challengeArray.count > 1, let scriptArr = challengeArray[1] as? [Any] {
            for item in scriptArr {
                if let s = item as? String {
                    interpreterJs = s
                    break
                }
            }
        }

        return BotGuardChallenge(
            program: program,
            messageId: messageId,
            interpreterHash: interpreterHash,
            globalName: globalName,
            interpreterJavascript: interpreterJs
        )
    }

    /// Parses the GenerateIT response.
    /// Response format: [base64IntegrityToken, expirationSeconds]
    private func parseIntegrityToken(_ raw: String) throws -> (String, Int) {
        guard let data = raw.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let tokenB64 = json[0] as? String,
              let expiresIn = json[1] as? Int else {
            throw BotGuardError.invalidResponse
        }

        // Convert base64 to Uint8Array JS representation
        let u8 = base64ToU8(tokenB64)
        return (u8, expiresIn)
    }

    /// Converts a base64 token to a JS Uint8Array string representation.
    private func base64ToU8(_ base64: String) -> String {
        let fixed = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: fixed) else {
            return "new Uint8Array([])"
        }
        let bytes = data.map { String($0) }.joined(separator: ",")
        return "new Uint8Array([\(bytes)])"
    }

    /// Descrambles challenge data: base64 decode + add 97 to each byte.
    private func descramble(_ scrambled: String) -> String {
        let fixed = scrambled
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: ".", with: "=")
        guard let data = Data(base64Encoded: fixed) else { return scrambled }
        let bytes = data.map { UInt8((Int($0) + 97) & 0xFF) }
        return String(data: Data(bytes), encoding: .utf8) ?? scrambled
    }
}

struct BotGuardChallenge: Sendable {
    let program: String
    let messageId: String?
    let interpreterHash: String?
    let globalName: String?
    let interpreterJavascript: String?
}

enum BotGuardError: Error, LocalizedError {
    case createFailed
    case generateITFailed
    case invalidResponse
    case descrambleFailed

    var errorDescription: String? {
        switch self {
        case .createFailed: return "BotGuard Create API call failed"
        case .generateITFailed: return "BotGuard GenerateIT API call failed"
        case .invalidResponse: return "Invalid BotGuard API response"
        case .descrambleFailed: return "Failed to descramble BotGuard program"
        }
    }
}
