//
//  YouTubeLocale.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Locale settings for InnerTube requests (region + language)
struct YouTubeLocale: Codable {
    let gl: String
    let hl: String

    nonisolated static let `default` = YouTubeLocale(gl: "US", hl: "en")
}
