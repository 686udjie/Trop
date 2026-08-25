//
//  LyricsRomanizer+Arabic.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Arabic → Latin.
/// Pointed text uses harakat: fatha/damma/kasra, tanwin, shadda doubling,
/// sun/moon letters, ta marbuta word-final "a".
/// Unpointed lyrics get inferred vowels from matres (ا = a, medial و = u,
/// non-initial ي = i) plus an epenthetic "a" between consonants, because
/// consonant-only output is unreadable (مرحبا → marhaba, not mrhba).
extension LyricsRomanizer {
    static func romanizeArabic(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var phonemes: [Phoneme] = []
        var startsWord: [Bool] = []
        var pendingWordStart = true
        var hasAnyPoints = false
        var i = 0
        /// The previous letter carried tanwin — a following bare alif is just
        /// its seat (شُكْرًا → "shukran", not "shukrana").
        var previousHadTanwin = false

        func endsVowel(_ character: String?) -> Bool {
            guard let last = character?.last else { return false }
            return "aeiou".contains(last)
        }

        while i < scalars.count {
            let value = scalars[i].value

            guard isArabicBase(value) else {
                if !isArabicPoint(value) { pendingWordStart = true }
                previousHadTanwin = false
                i += 1
                continue
            }

            var j = i + 1
            var haraka: String?
            var shadda = false
            while j < scalars.count, isArabicPoint(scalars[j].value) {
                hasAnyPoints = true
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

            // Bare alif right after a tanwin only seats the mark.
            if value == 0x0627 && haraka == nil && previousHadTanwin {
                previousHadTanwin = false
                i = j
                continue
            }

            // Silent lengthening matres: bare waw after a "u" phoneme and
            // bare yāʾ after an "i" phoneme just prolong the vowel.
            func lengtheningMatre(_ code: UInt32, _ suffix: String) -> Bool {
                haraka == nil && !shadda && value == code
                    && phonemes.last?.text.hasSuffix(suffix) == true
            }
            if lengtheningMatre(0x0648, "u") || lengtheningMatre(0x064A, "i") {
                previousHadTanwin = false
                i = j
                continue
            }

            var sound = arabicSound(value)

            // Sun-letter assimilation: the article's lām is silent before
            // a sun letter (الشمس → ash-shams). Pointed text demands a
            // shadda on the sun letter; unpointed lyrics accept an
            // alif+lām prefix as proof of the article.
            if value == 0x0644 && haraka == nil && !shadda,
               j < scalars.count, isArabicBase(scalars[j].value),
               isSunLetter(scalars[j].value) {
                let pointedAssimilation = nextHasShadda(scalars, j)
                let articlePrefix = i > 0
                    && scalars[i - 1].value == 0x0627
                    && isFirstBase(scalars, i - 1)
                if pointedAssimilation || (!hasAnyPoints && articlePrefix) {
                    i = j
                    continue
                }
            }

            // Word-final ta marbuta sounds "a"; alif carries a lengthening.
            if value == 0x0629 {
                var k = j
                while k < scalars.count, isArabicPoint(scalars[k].value) { k += 1 }
                sound = (k < scalars.count && (isArabicBase(scalars[k].value) || scalars[k].value == 0x0640)) ? "t" : "a"
            }
            if value == 0x0622 { haraka = haraka ?? "" }    // already "aa"

            // Unpointed matres carry vowels: ا أ إ آ ى ٱ map to vowel strings
            // in arabicConsonants; و and ي inflect by position.
            if haraka == nil && !shadda && !endsVowel(sound) {
                if value == 0x0648 {
                    sound = isFirstBase(scalars, i) ? "w" : "u"
                } else if value == 0x064A {
                    sound = isFirstBase(scalars, i) ? "y" : "i"
                }
            }

            let isVowelPhoneme = haraka != nil || shadda || endsVowel(sound)
            let emitted = sound + (haraka ?? "")
            let doubled = shadda && !sound.isEmpty ? sound + emitted : emitted
            phonemes.append((doubled, isVowelPhoneme))
            startsWord.append(pendingWordStart)
            pendingWordStart = false

            previousHadTanwin = haraka == "an" || haraka == "un" || haraka == "in"
            i = j
        }

        let finalPhonemes = hasAnyPoints
            ? phonemes
            : insertEpenthetic(in: phonemes, vowel: "a", startsWord: startsWord)
        return finalPhonemes.map(\.text).joined()
    }

    /// Whether the base letter at `index` is the word's first — a preceding
    /// base would exist otherwise.
    private static func isFirstBase(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        var k = index - 1
        while k >= 0, isArabicPoint(scalars[k].value) { k -= 1 }
        return k < 0 || !isArabicBase(scalars[k].value)
    }

    private static func isArabicBase(_ value: UInt32) -> Bool {
        (0x0621...0x064A).contains(value) || value == 0x0671
    }

    private static func isArabicPoint(_ value: UInt32) -> Bool {
        (0x064B...0x065F).contains(value) || value == 0x0670
    }

    /// Whether the base letter at `baseIndex` carries a shadda.
    private static func nextHasShadda(_ scalars: [Unicode.Scalar], _ baseIndex: Int) -> Bool {
        var k = baseIndex + 1
        while k < scalars.count, isArabicPoint(scalars[k].value) {
            if scalars[k].value == 0x0651 { return true }
            k += 1
        }
        return false
    }

    /// The 14 sun letters assimilate the definite article's lām.
    private static func isSunLetter(_ value: UInt32) -> Bool {
        switch value {
        case 0x062A, 0x062B, 0x062F, 0x0630, 0x0631, 0x0632, 0x0633, 0x0634,
             0x0635, 0x0636, 0x0637, 0x0638, 0x0644, 0x0646:
            return true
        default:
            return false
        }
    }

        /// Letter sounds; matres and hamza carriers map to their vowel strings.
    private static let arabicSounds: [UInt32: String] = [
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
        0x0639: "a",                                  // ع
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
        0x064A: "y",
        0x0671: "a"                                   // ٮ alef wasla
    ]

    private static func arabicSound(_ value: UInt32) -> String {
        arabicSounds[value] ?? ""
    }
}
