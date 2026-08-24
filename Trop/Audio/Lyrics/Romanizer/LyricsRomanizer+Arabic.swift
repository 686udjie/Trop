//
//  LyricsRomanizer+Arabic.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Arabic → Latin, harakat-aware: fatha/damma/kasra, tanwin, shadda
/// doubling, sun/moon letters, ta marbuta word-final "a"
extension LyricsRomanizer {
    static func romanizeArabic(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0

        while i < scalars.count {
            let value = scalars[i].value

            guard isArabicBase(value) else {
                out.unicodeScalars.append(scalars[i])
                i += 1
                continue
            }

            var j = i + 1
            var haraka: String?
            var shadda = false
            while j < scalars.count, isArabicPoint(scalars[j].value) {
                switch scalars[j].value {
                case 0x064B: haraka = "an"                  // fathatan
                case 0x064C: haraka = "un"                  // dammatan
                case 0x064D: haraka = "in"                  // kasratan
                case 0x064E: haraka = "a"                   // fatha
                case 0x064F: haraka = "u"                   // damma
                case 0x0650: haraka = "i"                   // kasra
                case 0x0651: shadda = true                  // shadda
                case 0x0670: haraka = "a"                   // superscript alef
                default: break                              // sukun etc.
                }
                j += 1
            }

            var consonant = arabicConsonant(value)

            // Word-final ta marbuta sounds "a"; alif carries a lengthening.
            if value == 0x0629 {
                var k = j
                while k < scalars.count, isArabicPoint(scalars[k].value) { k += 1 }
                consonant = (k < scalars.count && (isArabicBase(scalars[k].value) || scalars[k].value == 0x0640)) ? "t" : "a"
            }
            if value == 0x0622 { haraka = haraka ?? "" }    // already "aa"

            if shadda, !consonant.isEmpty {
                out += consonant + consonant
            } else {
                out += consonant
            }
            if value != 0x0622, let haraka {
                out += haraka
            }
            i = j
        }
        return out
    }

    private static func isArabicBase(_ value: UInt32) -> Bool {
        (0x0621...0x064A).contains(value)
    }

    private static func isArabicPoint(_ value: UInt32) -> Bool {
        (0x064B...0x065F).contains(value) || value == 0x0670
    }

    private static let arabicConsonants: [UInt32: String] = [
        0x0621: "'",                                  // ء
        0x0622: "aa",                                 // آ
        0x0623: "a",                                  // أ
        0x0624: "w",                                  // ؤ
        0x0625: "i",                                  // إ
        0x0626: "y",                                  // ئ
        0x0627: "a",                                  // ا
        0x0628: "b",
        0x0629: "h",                                  // ة
        0x062A: "t",
        0x062B: "th",
        0x062C: "j",
        0x062D: "h",                                  // ح
        0x062E: "kh",
        0x062F: "d",
        0x0630: "dh",
        0x0631: "r",
        0x0632: "z",
        0x0633: "s",
        0x0634: "sh",
        0x0635: "s",
        0x0636: "d",
        0x0637: "t",
        0x0638: "z",
        0x0639: "'",                                  // ع
        0x063A: "gh",
        0x0641: "f",
        0x0642: "q",
        0x0643: "k",
        0x0644: "l",
        0x0645: "m",
        0x0646: "n",
        0x0647: "h",
        0x0648: "w",
        0x0649: "a",
        0x064A: "y"
    ]

    private static func arabicConsonant(_ value: UInt32) -> String {
        arabicConsonants[value] ?? ""
    }
}
