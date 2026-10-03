//
// AuthService.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation

// Errors specific to session import and login verification
enum AuthError: LocalizedError {
    case verificationFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let error):
            return "Failed to verify login: \(error?.localizedDescription ?? "unknown")"
        }
    }
}

// Acts as the session and auth entry point for the rest of the app
actor AuthService {
    static let shared = AuthService()

    private let innerTube = InnerTubeClient.tropShared
    private let cookieStore = CookieStore()

// Imports a raw cookie string (e.g. from browser export) and persists it
  func importSession(from cookieString: String, dataSyncId: String? = nil) async throws {
    let auth = try SessionImporter.importSession(from: cookieString, dataSyncId: dataSyncId)
    await cookieStore.save(
        cookies: auth.cookies,
        sapisid: auth.sapisid,
        visitorData: auth.visitorData,
        dataSyncId: auth.dataSyncId
    )

    await innerTube.loadState(from: cookieStore)
  }

    // Probes `account/account_menu` to confirm the current session is still valid
    func verifyLogin() async throws -> Bool {
        do {
            let json = try await innerTube.accountMenu()
            guard let runs = BrowseLens.accountNameRuns(json) else { return false }
            return runs.contains { $0["text"] is String }
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
}
