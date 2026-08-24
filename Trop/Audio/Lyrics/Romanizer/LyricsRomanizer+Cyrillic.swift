//
//  LyricsRomanizer+Cyrillic.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Cyrillic → Latin (covers Russian, Ukrainian, Serbian, Bulgarian, etc)
extension LyricsRomanizer {
    static func romanizeCyrillic(_ text: String) -> String {
        var out = ""
        for char in text {
            let key = char.lowercased()
            if let mapped = cyrillicMap[key] {
                out += char.isUppercase ? mapped.capitalized : mapped
            } else {
                out.append(char)
            }
        }
        return out
    }

    private static let cyrillicMap: [String: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e",
        "ё": "yo", "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k",
        "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
        "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
        "э": "e", "ю": "yu", "я": "ya",
        "і": "i", "ї": "yi", "є": "ye", "ґ": "g"
    ]
}
