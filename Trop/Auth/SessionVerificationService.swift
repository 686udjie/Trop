//
// SessionVerificationService.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation

// Thin stateless helper that calls /account/account_menu and decides if the session is alive
actor SessionVerificationService {
    static let shared = SessionVerificationService()
    private let innerTube = InnerTube.shared

    // Calling this with no loaded session returns false rather than throwing
    func isSessionAlive() async -> Bool {
        do {
            let json = try await innerTube.accountMenu()
            guard let header = json["header"] as? [String: Any],
                  let renderer = header["musicAccountHeaderRenderer"] as? [String: Any],
                  let accountName = renderer["accountName"] as? [String: Any],
                  let runs = accountName["runs"] as? [[String: Any]],
                  runs.contains(where: { $0["text"] is String }) else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    func verifyAndThrow() async throws -> Bool {
        let json = try await innerTube.accountMenu()
        guard let header = json["header"] as? [String: Any],
              let renderer = header["musicAccountHeaderRenderer"] as? [String: Any],
              let accountName = renderer["accountName"] as? [String: Any],
              let runs = accountName["runs"] as? [[String: Any]],
              runs.contains(where: { $0["text"] is String }) else {
            throw SessionVerificationError.invalidAccountResponse
        }
        return true
    }
}

enum SessionVerificationError: LocalizedError {
    case invalidAccountResponse

    var errorDescription: String? {
        switch self {
        case .invalidAccountResponse:
            return "account/account_menu response did not contain a valid account name."
        }
    }
}
