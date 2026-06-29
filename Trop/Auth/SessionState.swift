//
// SessionState.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation

// Encapsulates all persistent session data for a logged-in YouTube Music user
struct SessionState: Codable {
    var cookie: String?          // Raw cookie string from browser export
    var sapisidHash: String?     // SAPISID cookie value (used for Authorization header)
    var visitorData: String?     // X-Goog-Visitor-Id header value
    var dataSyncId: String?      // YT data sync identifier
    var locale: YouTubeLocale    // Region + language settings

    var isLoggedIn: Bool {       // Convenience flag — true when SAPISID is present
        sapisidHash != nil
    }
}
