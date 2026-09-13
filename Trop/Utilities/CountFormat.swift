//
//  CountFormat.swift
//  Trop
//
//  Created by 686udjie on 13/09/2026.
//

import Foundation

/// Shared compact-count parsing and formatting. Consolidates `parseViewCount`
/// (YTItem) and the one-off views string in PlayerMenuSheet.
enum CountFormat {
    /// Parses compact counts like "1.2M views", "500K", "12,345" into an integer.
    static func parseCompactCount(_ text: String) -> Int64? {
        let pattern = "^([\\d,.]+)\\s*([KMBT]?)\\s*views?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges == 3,
              let numRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        let numStr = String(trimmed[numRange]).replacingOccurrences(of: ",", with: "")
        guard let number = Double(numStr) else { return nil }
        var multiplier: Double = 1
        if let sufRange = Range(match.range(at: 2), in: trimmed), !sufRange.isEmpty {
            switch trimmed[sufRange].uppercased() {
            case "K": multiplier = 1_000
            case "M": multiplier = 1_000_000
            case "B": multiplier = 1_000_000_000
            case "T": multiplier = 1_000_000_000_000
            default: break
            }
        }
        return Int64(number * multiplier)
    }
}

extension Int {
    /// "1,234,567 views" with decimal grouping.
    func formattedViews(suffix: String = " views") -> String {
        formatted(.number.grouping(.automatic)) + suffix
    }
}
