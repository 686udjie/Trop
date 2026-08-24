//
//  LyricsRomanizer+Hebrew.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Hebrew → Latin, nikud-aware: vowels come from niqqud when present
/// dagesh switches ב/כ/פ, shin/sin dots split ש
extension LyricsRomanizer {
    static func romanizeHebrew(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0

        while i < scalars.count {
            let value = scalars[i].value

            guard isHebrewBase(value) else {
                out.unicodeScalars.append(scalars[i])
                i += 1
                continue
            }

            // Collect the points attached to this letter.
            var j = i + 1
            var hasDagesh = false
            var sinDot = false
            var vowel: String?
            while j < scalars.count, isHebrewPoint(scalars[j].value) {
                switch scalars[j].value {
                case 0x05BC: hasDagesh = true               // dagesh
                case 0x05C2: sinDot = true                  // sin dot
                case 0x05B1: vowel = "e"                    // hataf segol
                case 0x05B2: vowel = "a"                    // hataf patah
                case 0x05B3: vowel = "o"                    // hataf qamats
                case 0x05B4: vowel = "i"                    // hiriq
                case 0x05B5: vowel = "e"                    // tsere
                case 0x05B6: vowel = "e"                    // segol
                case 0x05B7: vowel = "a"                    // patah
                case 0x05B8: vowel = "a"                    // qamats
                case 0x05B9: vowel = "o"                    // holam
                case 0x05BB: vowel = "u"                    // qubuts
                case 0x05B0: if vowel == nil { vowel = "" } // sheva (silent)
                default: break                              // cantillation etc.
                }
                j += 1
            }

            // Matres lectionis carry the vowel themselves.
            if value == 0x05D5 {                            // ו
                if hasDagesh {
                    out += "u"                              // shuruk
                } else if vowel == "o" {
                    out += "o"                              // holam male
                } else {
                    out += "v"
                    out += vowel ?? ""
                }
                i = j
                continue
            }
            if value == 0x05D9, vowel == "i" {              // יִ
                out += "i"
                i = j
                continue
            }

            var consonant = hebrewConsonant(value, hasDagesh: hasDagesh, sinDot: sinDot)

            // Word-final ה is silent.
            if value == 0x05D4 {
                var k = j
                while k < scalars.count, isHebrewPoint(scalars[k].value) { k += 1 }
                if k >= scalars.count || !isHebrewBase(scalars[k].value) {
                    consonant = vowel == nil ? "" : "h"
                }
            }

            out += consonant
            out += vowel ?? ""
            i = j
        }
        return out
    }

    private static func isHebrewBase(_ value: UInt32) -> Bool {
        (0x05D0...0x05EA).contains(value)
    }

    /// Niqqud, dagesh, shin/sin dots and cantillation marks
    private static func isHebrewPoint(_ value: UInt32) -> Bool {
        guard (0x0591...0x05C7).contains(value) else { return false }
        return value != 0x05BE && value != 0x05C0 && value != 0x05C3 && value != 0x05C6
    }

    private static func hebrewConsonant(_ value: UInt32, hasDagesh: Bool, sinDot: Bool) -> String {
        switch value {
        case 0x05D0: return "'"                       // א
        case 0x05D1: return hasDagesh ? "b" : "v"     // ב
        case 0x05D2: return "g"                       // ג
        case 0x05D3: return "d"                       // ד
        case 0x05D4: return "h"                       // ה
        case 0x05D5: return "v"                       // ו
        case 0x05D6: return "z"                       // ז
        case 0x05D7: return "ch"                      // ח
        case 0x05D8: return "t"                       // ט
        case 0x05D9: return "y"                       // י
        case 0x05DA: return "ch"                      // ך
        case 0x05DB: return hasDagesh ? "k" : "ch"    // כ
        case 0x05DC: return "l"                       // ל
        case 0x05DE: return "m"                       // מ
        case 0x05DD: return "m"                       // ם
        case 0x05E0: return "n"                       // נ
        case 0x05DF: return "n"                       // ן
        case 0x05E1: return "s"                       // ס
        case 0x05E2: return "'"                       // ע
        case 0x05E3: return "f"                       // ף
        case 0x05E4: return hasDagesh ? "p" : "f"     // פ
        case 0x05E6: return "ts"                      // צ
        case 0x05E5: return "ts"                      // ץ
        case 0x05E7: return "k"                       // ק
        case 0x05E8: return "r"                       // ר
        case 0x05E9: return sinDot ? "s" : "sh"       // ש
        case 0x05EA: return "t"                       // ת
        default: return ""
        }
    }
}
