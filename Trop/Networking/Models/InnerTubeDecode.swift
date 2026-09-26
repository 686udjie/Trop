//
//  InnerTubeDecode.swift
//  Trop
//
//  Created by 686udjie on 26/09/2026.
//

import Foundation

enum InnerTubeDecode {
    /// Walks a path like ["contents", "singleColumnBrowseResultsRenderer"].
    /// Numeric components index into arrays ("0", "tabs.0" not supported —
    /// pass arrays explicitly via `array(at:)`).
    static func value(at path: [String], in dict: [String: Any]) -> Any? {
        var current: Any? = dict
        for key in path {
            guard let d = current as? [String: Any] else { return nil }
            current = d[key]
        }
        return current
    }

    static func dict(at path: [String], in dict: [String: Any]) -> [String: Any]? {
        value(at: path, in: dict) as? [String: Any]
    }

    static func array(at path: [String], in dict: [String: Any]) -> [[String: Any]]? {
        value(at: path, in: dict) as? [[String: Any]]
    }

    static func string(at path: [String], in dict: [String: Any]) -> String? {
        value(at: path, in: dict) as? String
    }

    /// `lengthSeconds`-style fields arrive as either String or Int.
    static func intFromStringOrInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    /// Runs-text that tolerates `{runs: [...]}` missing, `text` missing, or
    /// the whole dict being a plain string (some endpoints inline it).
    static func runsTextTolerant(_ dict: Any?) -> String? {
        if let s = dict as? String { return s }
        guard let d = dict as? [String: Any] else { return nil }
        if let runs = d["runs"] as? [[String: Any]] {
            // Join all runs — some titles split across styled runs.
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            if !joined.isEmpty { return joined }
        }
        // Fallbacks YTM sometimes uses instead of runs.
        if let s = d["simpleText"] as? String, !s.isEmpty { return s }
        if let s = d["text"] as? String, !s.isEmpty { return s }
        return nil
    }

    /// Largest thumbnail across all known InnerTube thumbnail envelopes.
    /// Never crashes on unexpected shapes — returns nil.
    static func thumbnailURLTolerant(_ dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        // musicThumbnailRenderer.thumbnail.thumbnails
        if let thumb = dict["thumbnail"] as? [String: Any],
           let music = thumb["musicThumbnailRenderer"] as? [String: Any],
           let inner = music["thumbnail"] as? [String: Any],
           let list = inner["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        // thumbnail.thumbnails
        if let thumb = dict["thumbnail"] as? [String: Any],
           let list = thumb["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        // bare thumbnails
        if let list = dict["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        // croppedSquareThumbnail
        if let cropped = dict["croppedSquareThumbnail"] as? [String: Any],
           let list = cropped["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        return nil
    }

    /// Logs unexpected shapes once per call site so YTM changes surface in
    /// diagnostics instead of silently emptying a page.
    static func warnOnce(_ message: String) {
        Log.innerTube.notice("\(message)")
    }
}
