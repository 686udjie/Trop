//
//  LyricsRomanizer+Thai.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Thai → Latin, RTGS-style approximation: initial/final consonant forms,
/// preposed and following vowels, tone marks skipped.
extension LyricsRomanizer {
    static func romanizeThai(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var lastConsonantRange: Range<String.Index>?
        var i = 0

        while i < scalars.count {
            let value = scalars[i].value

            // Tone marks & diacritics are not romanized; ์ silences the
            // preceding consonant.
            switch value {
            case 0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E4C, 0x0E47, 0x0E38...0x0E3A:
                if value == 0x0E4C, let range = lastConsonantRange {
                    out.removeSubrange(range)
                    lastConsonantRange = nil
                }
                i += 1
                continue
            case 0x0E4F: // ๆ repeats the previous word — skipped for simplicity
                i += 1
                continue
            default:
                break
            }

            // Preposed vowels belong before the following consonant.
            switch value {
            case 0x0E40: out += "e"; i += 1; continue
            case 0x0E41: out += "ae"; i += 1; continue
            case 0x0E42: out += "o"; i += 1; continue
            case 0x0E43, 0x0E44: out += "ai"; i += 1; continue
            default: break
            }

            // Following vowels.
            switch value {
            case 0x0E30: out += "a"; i += 1; continue
            case 0x0E32: out += "aa"; i += 1; continue
            case 0x0E33: out += "am"; i += 1; continue
            case 0x0E31: out += "a"; i += 1; continue
            case 0x0E35: out += "i"; i += 1; continue
            case 0x0E36: out += "ue"; i += 1; continue
            case 0x0E37: out += "ue"; i += 1; continue
            case 0x0E38: out += "u"; i += 1; continue
            default: break
            }

            if let initial = thaiInitials[value] {
                // Use the final form when the syllable ends here.
                var k = i + 1
                while k < scalars.count,
                      (0x0E31...0x0E3A).contains(scalars[k].value) || (0x0E47...0x0E4E).contains(scalars[k].value) {
                    k += 1
                }
                let isSyllableEnd = k >= scalars.count || thaiInitials[scalars[k].value] != nil || scalars[k].value == 0x0E50
                let rendered = (!isSyllableEnd ? initial : (thaiFinals[value] ?? initial))
                let start = out.endIndex
                out += rendered
                lastConsonantRange = start..<out.endIndex
                i += 1
                continue
            }

            out.unicodeScalars.append(scalars[i])
            i += 1
        }
        return out
    }

    private static let thaiInitials: [UInt32: String] = [
        0x0E01: "k", 0x0E02: "kh", 0x0E03: "kh", 0x0E04: "kh", 0x0E05: "ng",
        0x0E06: "ch", 0x0E07: "ch", 0x0E08: "ch", 0x0E09: "s", 0x0E0A: "ch",
        0x0E0B: "s", 0x0E0C: "t", 0x0E0D: "y", 0x0E0E: "d", 0x0E0F: "t",
        0x0E10: "th", 0x0E11: "th", 0x0E12: "th", 0x0E13: "n", 0x0E14: "d",
        0x0E15: "t", 0x0E16: "th", 0x0E17: "th", 0x0E18: "th", 0x0E19: "n",
        0x0E1A: "b", 0x0E1B: "p", 0x0E1C: "ph", 0x0E1D: "f", 0x0E1E: "ph",
        0x0E1F: "f", 0x0E20: "ph", 0x0E21: "m", 0x0E22: "y", 0x0E23: "r",
        0x0E25: "l", 0x0E26: "l", 0x0E27: "w", 0x0E28: "s", 0x0E29: "s",
        0x0E2A: "s", 0x0E2B: "h", 0x0E2D: "o", 0x0E2E: "h"
    ]

    private static let thaiFinals: [UInt32: String] = [
        0x0E01: "k", 0x0E02: "k", 0x0E03: "k", 0x0E04: "k", 0x0E05: "ng",
        0x0E06: "t", 0x0E07: "t", 0x0E08: "t", 0x0E09: "", 0x0E0A: "t",
        0x0E0B: "", 0x0E0C: "t", 0x0E0D: "i", 0x0E0E: "t", 0x0E0F: "t",
        0x0E10: "t", 0x0E11: "t", 0x0E12: "t", 0x0E13: "n", 0x0E14: "t",
        0x0E15: "t", 0x0E16: "t", 0x0E17: "t", 0x0E18: "t", 0x0E19: "n",
        0x0E1A: "p", 0x0E1B: "p", 0x0E1C: "", 0x0E1D: "", 0x0E1E: "p",
        0x0E1F: "", 0x0E20: "p", 0x0E21: "m", 0x0E22: "i", 0x0E23: "n",
        0x0E25: "n", 0x0E26: "n", 0x0E27: "o", 0x0E28: "", 0x0E29: "",
        0x0E2A: "", 0x0E2B: "", 0x0E2D: "", 0x0E2E: ""
    ]
}
