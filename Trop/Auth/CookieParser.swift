//
//  CookieParser.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation

/// Splits a raw `Set-Cookie`-style string into name→value pairs.
/// Consolidates the character-identical helpers in CookieStore and AuthService.
enum CookieParser {
    static func parse(_ cookieString: String) -> [String: String] {
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
