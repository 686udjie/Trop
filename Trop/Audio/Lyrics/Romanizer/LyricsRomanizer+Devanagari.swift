//
//  LyricsRomanizer+Devanagari.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Devanagari → Latin (Hindi / Marathi / Nepali): matras, virama conjuncts
/// nukta variants, inherent-"a" with word-final deletion
extension LyricsRomanizer {
    static func romanizeDevanagari(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0

        func isLetterish(_ value: UInt32) -> Bool {
            isDevanagariConsonant(value)
                || devanagariIndependentVowel(value) != nil
                || (0x0900...0x094D).contains(value)
        }

        while i < scalars.count {
            let value = scalars[i].value

            if isDevanagariConsonant(value) {
                var j = i + 1
                var hasNukta = false
                var hasVirama = false
                var matra: String?

                while j < scalars.count, isDevanagariSign(scalars[j].value) {
                    let point = scalars[j].value
                    if point == 0x093C {
                        hasNukta = true
                    } else if point == 0x094D {
                        hasVirama = true
                        j += 1
                        break
                    } else if let m = devanagariMatraVowel(point), matra == nil {
                        matra = m
                    } else if point == 0x0901 || point == 0x0902 || point == 0x0900 {
                        break
                    }
                    j += 1
                }

                out += devanagariConsonant(value, hasNukta: hasNukta)

                if hasVirama {
                    // Conjunct: no inherent vowel.
                } else if let matra {
                    out += matra
                } else {
                    // Inherent "a", dropped word-finally.
                    if j < scalars.count, isLetterish(scalars[j].value) {
                        out += "a"
                    }
                }

                // Trailing anusvara/visarga after the vowel.
                while j < scalars.count, (0x0900...0x0903).contains(scalars[j].value) {
                    let sign = scalars[j].value
                    out += sign == 0x0903 ? "h" : "n"
                    j += 1
                }
                i = j
                continue
            }

            if let vowel = devanagariIndependentVowel(value) {
                out += vowel
                i += 1
                continue
            }

            out.unicodeScalars.append(scalars[i])
            i += 1
        }
        return out
    }

    private static func isDevanagariConsonant(_ value: UInt32) -> Bool {
        (0x0915...0x0939).contains(value)
    }

    private static let devanagariConsonants: [UInt32: String] = [
        0x0915: "k", 0x0916: "kh", 0x0917: "g", 0x0918: "gh", 0x0919: "ng",
        0x091A: "ch", 0x091B: "chh", 0x091C: "j", 0x091D: "jh", 0x091E: "ny",
        0x091F: "t", 0x0920: "th", 0x0921: "d", 0x0922: "dh", 0x0923: "n",
        0x0924: "t", 0x0925: "th", 0x0926: "d", 0x0927: "dh", 0x0928: "n",
        0x092A: "p", 0x092B: "ph", 0x092C: "b", 0x092D: "bh", 0x092E: "m",
        0x092F: "y", 0x0930: "r", 0x0932: "l", 0x0933: "l", 0x0935: "v",
        0x0936: "sh", 0x0937: "sh", 0x0938: "s", 0x0939: "h"
    ]

    /// Nukta variants (क़ ज़ ड़ फ़ …).
    private static let devanagariNuktaOverrides: [UInt32: String] = [
        0x0915: "q",
        0x091C: "z",
        0x0921: "r",
        0x092B: "f"
    ]

    private static func devanagariConsonant(_ value: UInt32, hasNukta: Bool) -> String {
        if hasNukta, let overridden = devanagariNuktaOverrides[value] {
            return overridden
        }
        return devanagariConsonants[value] ?? ""
    }

    private static func devanagariMatraVowel(_ value: UInt32) -> String? {
        switch value {
        case 0x093E: return "aa"
        case 0x093F: return "i"
        case 0x0940: return "ii"
        case 0x0941: return "u"
        case 0x0942: return "uu"
        case 0x0943: return "ri"
        case 0x0944: return "rii"
        case 0x0945, 0x0946: return "e"
        case 0x0947, 0x0948: return "ai"
        case 0x0949, 0x094A: return "o"
        case 0x094B, 0x094C: return "au"
        default: return nil
        }
    }

    private static func devanagariIndependentVowel(_ value: UInt32) -> String? {
        switch value {
        case 0x0905: return "a"
        case 0x0906: return "aa"
        case 0x0907: return "i"
        case 0x0908: return "ii"
        case 0x0909: return "u"
        case 0x090A: return "uu"
        case 0x090B: return "ri"
        case 0x090C: return "lri"
        case 0x090D, 0x090F: return "e"
        case 0x090E, 0x0910: return "ai"
        case 0x0911, 0x0912: return "o"
        case 0x0913, 0x0914: return "au"
        default: return nil
        }
    }

    private static func isDevanagariSign(_ value: UInt32) -> Bool {
        (0x0900...0x094D).contains(value) && !isDevanagariConsonant(value)
            || (0x093C...0x094D).contains(value)
    }
}
