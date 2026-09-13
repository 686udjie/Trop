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

    /// Compact "45s" / "3m 20s" for scrobble settings.
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
}
