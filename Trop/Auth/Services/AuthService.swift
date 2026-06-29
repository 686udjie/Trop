//
// AuthService.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation

// Errors specific to session import and login verification
enum AuthError: LocalizedError {
    case invalidCookie
    case sapisidNotFound
    case verificationFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .invalidCookie:
            return "Cookie string is empty or invalid"
        case .sapisidNotFound:
            return "Both SAPISID and __Secure-3PSAPISID missing from cookies"
        case .verificationFailed(let error):
            return "Failed to verify login: \(error?.localizedDescription ?? "unknown")"
        }
    }
}

// Acts as the session and auth entry point for the rest of the app
actor AuthService {
    static let shared = AuthService()

    private let innerTube = InnerTube.shared
    private let cookieStore = CookieStore()

// Imports a raw cookie string (e.g. from browser export), extracts SAPISID + visitorData, and persists
  func importSession(from cookieString: String) async throws {
    guard !cookieString.isEmpty else {
      throw AuthError.invalidCookie
    }

    let cookies = parseCookieString(cookieString)
    let sapisid = extractSAPISID(from: cookies)
    let visitorData = extractVisitorData(from: cookies)

    await cookieStore.save(cookies: cookies, sapisid: sapisid, visitorData: visitorData)

    await innerTube.loadState(from: cookieStore)
  }

    // Probes `account/account_menu` to confirm the current session is still valid
    func verifyLogin() async throws -> Bool {
        do {
            let json = try await innerTube.accountMenu()
            guard let header = json["header"] as? [String: Any] else { return false }
            guard let accountData = header["musicAccountHeaderRenderer"] as? [String: Any] else { return false }
            guard let accountName = accountData["accountName"] as? [String: Any] else { return false }
            guard let text = accountName["runs"] as? [[String: Any]] else { return false }
            return text.contains { $0["text"] is String }
        } catch {
            throw AuthError.verificationFailed(error)
        }
    }

    // Quick synchronous-ish check — reads from the local CookieStore wrapper
    func isLoggedIn() async -> Bool {
        await cookieStore.isLoggedIn()
    }

    // Re-hydrates InnerTube from whatever is currently saved in the CookieStore
    func loadPersistedSession() async {
        await innerTube.loadState(from: cookieStore)
    }

// Wipes cookies and SAPISID from both CookieStore and the running InnerTube instance
  func logout() async {
    await cookieStore.clear()
    await innerTube.loadState(from: cookieStore)
  }

    // Prefer __Secure-3PSAPISID cookie over legacy SAPISID
    private func extractSAPISID(from cookies: [String: String]) -> String? {
        if let sapisid = cookies["__Secure-3PSAPISID"] {
            return sapisid
        }
        return cookies["SAPISID"]
    }

    // YouTube sets this as a plain cookie; reuse it as the visitorData header
    private func extractVisitorData(from cookies: [String: String]) -> String? {
        cookies["visitor_data"]
    }

    // Splits a raw `Set-Cookie`-style string into name→value pairs
    private func parseCookieString(_ cookieString: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = cookieString.split(separator: ";")
        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }
        return result
    }
}
