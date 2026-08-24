//
//  LyricsProvider.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

/// A normalized query used to look up lyrics across providers
struct LyricsQuery {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval

    var durationSeconds: Int { Int(duration) }
}

/// Common interface implemented by every lyrics source.
protocol LyricsProvider: Sendable {
    var id: String { get }
    var name: String { get }
    func fetch(query: LyricsQuery) async throws -> [LyricLine]
}

enum LyricsParsing {
    /// Parses an `[mm:ss.xx]` or `[mm:ss]` timestamp at the start of a line
    static func parseLrcTimestamp(_ line: String) -> (time: TimeInterval, text: String)? {
        // Match one or more leading [..] tags
        let pattern = #"^(?:\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\])+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return nil }

        // The last matched tag holds the time we care about
        let tagPattern = #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern) else { return nil }
        let tagMatches = tagRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        guard let last = tagMatches.last else { return nil }
        let mins = Int((line as NSString).substring(with: last.range(at: 1))) ?? 0
        let secs = Int((line as NSString).substring(with: last.range(at: 2))) ?? 0
        let fracRange = last.range(at: 3)
        let fracStr = fracRange.location != NSNotFound ? (line as NSString).substring(with: fracRange) : "0"
        // Normalize fractional part to seconds (supports 2 or 3 digit centiseconds/milliseconds)
        let frac = Double("0.\(fracStr)") ?? 0
        let time = TimeInterval(mins * 60 + secs) + frac

        let end = match.range.location + match.range.length
        let text = String(line[line.index(line.startIndex, offsetBy: end)...])
            .trimmingCharacters(in: .whitespaces)
        return (time, text)
    }

    /// Split a raw LRC string into lines. Blank timestamped lines are kept —
    /// they mark instrumental spans (like Metrolist's isBlank entries).
    static func parseLrc(_ raw: String) -> [LyricLine] {
        raw.split(whereSeparator: \.isNewline).map(String.init).compactMap { line in
            guard let (time, text) = parseLrcTimestamp(line) else { return nil }
            return LyricLine(text: text, startTime: time)
        }
    }

    /// Parses stored lyrics text — LRC if timestamped, otherwise plain lines.
    static func parseStoredText(_ raw: String) -> [LyricLine] {
        let lrc = parseLrc(raw)
        if !lrc.isEmpty { return lrc }
        return raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(text: $0, startTime: nil) }
    }

    /// Serializes lines back to LRC/plain text for storage and editing.
    static func serializeLines(_ lines: [LyricLine]) -> String {
        let synced = lines.contains { $0.startTime != nil }
        return lines.map { line in
            guard synced, let t = line.startTime else { return line.text }
            let minutes = Int(t) / 60
            let seconds = Int(t) % 60
            let centis = Int((t - floor(t)) * 100)
            return String(format: "[%02d:%02d.%02d]", minutes, seconds, centis) + line.text
        }
        .joined(separator: "\n")
    }

    /// Plain text without timestamps — what "Copy" puts on the clipboard.
    static func plainText(_ lines: [LyricLine]) -> String {
        lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
