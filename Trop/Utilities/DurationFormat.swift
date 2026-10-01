//
//  DurationFormat.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation

/// Single home for duration parsing and formatting. Consolidates the three
/// `m:ss` clock parsers (`YTItem.parseTime`, `DetailParser.parseDuration`,
/// `LibraryBrowseParser.parseDuration`) and the three formatters
/// (`Int.formattedDuration`, `FullPlayerView.timeString`,
/// `LastFMSettingsView.formatDuration`).
enum DurationFormat {
    /// Parses "m:ss" / "h:mm:ss" clock strings ("." and "," tolerated as
    /// separators, matching the historical parsers); nil when unparseable.
    static func parseClock(_ text: String) -> Int? {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ":.,")).compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// "m:ss" for playback positions. Never empty; clamps negatives and
    /// non-finite values to "0:00".
    static func playbackTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = max(Int(t), 0)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Parses spoken durations like "1 hr 23 mins", "45 mins" or "2 hours".
    static func parseSpoken(_ text: String) -> Int? {
        let lower = text.lowercased()
        var total = 0
        var found = false
        // Matches "<number> <unit>" pairs; units cover hr/hour/h, min/m, sec/s.
        let pattern = "(\\d+)\\s*(hours?|hrs?|\\bh\\b|minutes?|mins?|\\bm\\b|seconds?|secs?|\\bs\\b)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        for match in regex.matches(in: lower, range: range) {
            guard let numRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower),
                  let number = Int(lower[numRange]) else { continue }
            let unit = String(lower[unitRange])
            if unit.hasPrefix("h") {
                total += number * 3600
                found = true
            } else if unit.hasPrefix("m") {
                total += number * 60
                found = true
            } else if unit.hasPrefix("s") {
                total += number
                found = true
            }
        }
        return found ? total : nil
    }
    static func shortDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

extension Int {
    /// "m:ss" / "h:mm:ss"; empty string when not positive.
    var formattedDuration: String {
        guard self > 0 else { return "" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let secs = self % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    var wordsDuration: String {
        guard self > 0 else { return "" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        switch (hours, minutes) {
        case (0, 0):
            return "\(self % 60) sec"
        case (0, _):
            return "\(minutes) min"
        case (_, 0):
            return "\(hours) h"
        default:
            return "\(hours) h \(minutes) min"
        }
    }
}
