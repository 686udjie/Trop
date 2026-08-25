//
//  LyricsRomanizer+Hebrew.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Hebrew → Latin.
/// Pointed words (with niqqud) go through the nikud-aware engine below.
/// Unpointed modern Hebrew — most lyrics — goes through a phonetic engine:
/// a common-words dictionary plus ktiv-male letter rules (ו → o/u, י → i,
/// final ה → a, positional ב/כ/פ, ע/א as vowel markers), because accurate
/// consonant-only transliteration is unreadable.
extension LyricsRomanizer {
    static func romanizeHebrew(_ text: String) -> String {
        // Split into words and separators; route each word individually.
        var out = ""
        var word = ""
        func flushWord() {
            guard !word.isEmpty else { return }
            out += word.unicodeScalars.contains(where: { isHebrewPoint($0.value) })
                ? romanizePointedHebrew(word)
                : romanizeUnpointedHebrewWord(word)
            word = ""
        }

        for scalar in text.unicodeScalars {
            if isHebrewBase(scalar.value) || isHebrewPoint(scalar.value) {
                word.unicodeScalars.append(scalar)
            } else {
                flushWord()
                out.unicodeScalars.append(scalar)
            }
        }
        flushWord()
        return out
    }

    // MARK: - Unpointed (modern) Hebrew

    /// Common lyric words — full-vowel transliterations the letter rules
    /// can't infer.
    private static let hebrewWordOverrides: [String: String] = [
        "אני": "ani", "את": "at", "אתה": "ata", "אנחנו": "anachnu",
        "הוא": "hu", "היא": "hi", "הם": "hem", "הנה": "hine",
        "יש": "yesh", "אין": "ein", "ישלי": "yesh li",
        "כן": "ken", "לא": "lo", "אולי": "ulai", "רק": "rak",
        "אז": "az", "עכשיו": "achshav", "עוד": "od", "כבר": "kvar",
        "מה": "ma", "למה": "lama", "כמה": "kama", "מי": "mi",
        "גם": "gam", "אבל": "aval", "שלך": "shelacha", "שלי": "sheli",
        "שלנו": "shelanu", "לך": "lecha", "איתך": "itach",
        "אותי": "oti", "אותך": "otacha", "אותו": "oto", "אותה": "ota",
        "לי": "li", "לנו": "lanu", "בשבילך": "bishvilecha",
        "אהבה": "ahava", "אוהב": "ohev", "אוהבת": "ohevet",
        "שלום": "shalom", "חיים": "chayim", "החיים": "hachayim",
        "לב": "lev", "ליבי": "libi", "הלב": "halev",
        "לילה": "laila", "יום": "yom", "בוקר": "boker", "ערב": "erev",
        "טוב": "tov", "אמת": "emet", "שקר": "sheker",
        "חלום": "chalom", "חלמתי": "chalamti", "דמעות": "dmaot",
        "ודמעת": "udmaot", "שילמתי": "shilamti", "מחכתי": "mechaketi",
        "מחכת": "mechaka", "מחכות": "mechakot", "מחכה": "mechaka",
        "רוצה": "rotze", "ללכת": "lalechet", "ביחד": "beyachad",
        "ושוב": "veshuv", "שוב": "shuv", "פשוט": "pashut",
        "הלך": "halach", "מזמן": "mizman", "אמר": "amar",
        "תן": "ten", "סליחה": "slicha", "בבקשה": "bevakasha",
        "תודה": "toda", "ולפעמים": "ulifamim", "לפעמים": "lifamim",
        "בינינו": "beineinu", "שנאה": "sina", "הוספתי": "hosafati",
        "להודות": "lehodot", "מנגן": "menagen", "על": "al",
        "משוחרר": "meshucharar", "החרדות": "hachardot",
        "נשברה": "nishbera", "חושב": "choshev", "יודע": "yodea",
        "בוכה": "boche", "שיר": "shir", "לבד": "levad",
        "בלבד": "bilvad", "איתי": "iti", "כאב": "ke'ev"
    ]

    private static func romanizeUnpointedHebrewWord(_ word: String) -> String {
        let scalars = Array(word.unicodeScalars.filter { isHebrewBase($0.value) })
        guard !scalars.isEmpty else { return word }
        let bare = String(String.UnicodeScalarView(scalars))
        if let hit = hebrewWordOverrides[bare] { return hit }

        var phonemes: [Phoneme] = []
        var i = 0

        func base(_ idx: Int) -> UInt32 {
            idx < scalars.count ? scalars[idx].value : 0
        }

        while i < scalars.count {
            let value = base(i)
            let isLast = i == scalars.count - 1
            let next = base(i + 1)
            let prev = i > 0 ? base(i - 1) : 0

            func add(_ text: String, vowel: Bool = false) {
                phonemes.append((text, vowel))
            }

            switch value {
            case 0x05D0: // א — vowel marker in ktiv male
                if i == 0, next == 0x05D5 {
                    add("o", vowel: true); i += 2; continue
                }
                if i == 0, next == 0x05D9 {
                    add("ei", vowel: true); i += 1; continue
                }
                add("a", vowel: true)
            case 0x05D4: // ה
                if i == 0, next == 0x05D5 {
                    add("ho", vowel: true); i += 2; continue
                }
                if i == 0, next == 0x05D9 {
                    add("hi", vowel: true); i += 2; continue
                }
                if i == 0 {
                    add("ha", vowel: true)
                } else if isLast {
                    add("a", vowel: true)
                } else {
                    add("h")
                }
            case 0x05D5: // ו
                if i == 0 {
                    add("ve", vowel: true)
                } else if prev == 0x05D5 {
                    add("v")
                } else if isLast {
                    add("u", vowel: true)
                } else {
                    add("o", vowel: true)
                }
            case 0x05D9: // י
                if i == 0 {
                    add("y")
                } else {
                    add("i", vowel: true)
                }
            case 0x05E2: // ע — silent glottal, usually a vowel marker
                if i == 0, next == 0x05D9 {
                    // י carries the vowel
                } else {
                    add("a", vowel: true)
                }
            case 0x05D1: // ב
                add(i == 0 ? "b" : "v")
            case 0x05DB, 0x05DA: // כ / ך
                if value == 0x05DA {
                    add("ech", vowel: true) // לך → lech
                } else {
                    add(i == 0 ? "k" : "ch")
                }
            case 0x05E4, 0x05E3: // פ / ף
                add(i == 0 && value == 0x05E4 ? "p" : "f")
            default:
                if let mapped = unpointedSimple[value] {
                    add(mapped)
                } else {
                    add(UnicodeScalar(value).map(String.init) ?? "")
                }
            }
            i += 1
        }

        // Epenthetic "e" between adjacent consonants keeps ktiv-chaser
        // words readable (משחר → meshecher, מזמן → mezemen).
        phonemes = insertEpenthetic(in: phonemes, vowel: "e")

        return phonemes.map(\.text).joined()
    }

    /// Context-free one-letter sounds for the unpointed fallback rules.
    /// Letters whose reading depends on position (ב כ ך פ ף ו י ע א ה)
    /// are handled in the switch above.
    private static let unpointedSimple: [UInt32: String] = [
        0x05D2: "g", 0x05D3: "d", 0x05D6: "z", 0x05D7: "ch", 0x05D8: "t",
        0x05DC: "l", 0x05DE: "m", 0x05DD: "m", 0x05E0: "n", 0x05DF: "n",
        0x05E1: "s", 0x05E6: "ts", 0x05E5: "ts", 0x05E7: "k", 0x05E8: "r",
        0x05E9: "sh", 0x05EA: "t"
    ]

    // MARK: - Pointed (nikud) Hebrew

    static func romanizePointedHebrew(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        var atWordStart = true
        var previousHadSheva = false
        /// Previous letter carried a long vowel — a sheva after it is vocal.
        var previousVowelLong = false
        var previousNikud: UInt32?

        while i < scalars.count {
            let value = scalars[i].value

            guard isHebrewBase(value) else {
                out.unicodeScalars.append(scalars[i])
                atWordStart = true
                previousVowelLong = false
                i += 1
                continue
            }

            // Collect the points attached to this letter.
            var j = i + 1
            var hasDagesh = false
            var sinDot = false
            var nikud: UInt32?
            while j < scalars.count, isHebrewPoint(scalars[j].value) {
                switch scalars[j].value {
                case 0x05BC: hasDagesh = true               // dagesh
                case 0x05C2: sinDot = true                  // sin dot
                case 0x05B0...0x05BB: nikud = scalars[j].value
                default: break                              // cantillation etc.
                }
                j += 1
            }

            let context = NikudContext(
                atWordStart: atWordStart,
                previousHadSheva: previousHadSheva,
                previousVowelLong: previousVowelLong,
                hasDagesh: hasDagesh,
                isBegadkefat: isHebrewBegadkefat(value),
                nextBaseIndex: j,
                scalars: scalars
            )
            let vowelResult = hebrewVowel(for: nikud, context: context)
            var vowel = vowelResult.sound
            let hadSheva = nikud == 0x05B0

            // ו — shuruk / holam male / consonant vav.
            if value == 0x05D5 {
                if hasDagesh {
                    out += "u"
                } else if nikud == 0x05B9 {
                    out += "o"
                } else if nikud == nil, endsWithVowel(out, "ou") {
                    // Bare vav prolongs an o/u vowel — silent mater.
                } else {
                    out += "v"
                    out += vowel
                }
                previousHadSheva = hadSheva
                previousVowelLong = true // shuruk is long
                previousNikud = nikud
                atWordStart = false
                i = j
                continue
            }

            // יִ — hiriq male; word-initially the yod is a consonant ("yi").
            if value == 0x05D9, nikud == 0x05B4 {
                out += atWordStart ? "yi" : "i"
                previousHadSheva = false
                previousVowelLong = true // hiriq male is long
                previousNikud = nikud
                atWordStart = false
                i = j
                continue
            }

            var consonant = hebrewConsonant(value, hasDagesh: hasDagesh, sinDot: sinDot)

            // Silent glottals: alef/`ayin carry vowels but no sound of their
            // own in casual romanization — EXCEPT hataf-vowel alef/`ayin
            // right after another vowel keeps its break audible
            // (הַאֲזִין → ha'azin).
            if value == 0x05D0 || value == 0x05E2 {
                consonant = ""
                let isHataf = nikud == 0x05B1 || nikud == 0x05B2 || nikud == 0x05B3
                if isHataf, !vowel.isEmpty, endsWithVowel(out, "aeiou") {
                    out += "'"
                }
            }

            // Word-final ה is silent.
            if value == 0x05D4 {
                var k = j
                while k < scalars.count, isHebrewPoint(scalars[k].value) { k += 1 }
                if k >= scalars.count || !isHebrewBase(scalars[k].value) {
                    consonant = ""
                }
            }

            // Bare matres: silent yod after "i", male "i" after tsere/segol,
            // silent vav after "o"/"u".
            if nikud == nil {
                if value == 0x05D9 {
                    if endsWithVowel(out, "i") {
                        consonant = ""
                    } else if previousNikud == 0x05B5 || previousNikud == 0x05B6 {
                        consonant = ""
                        vowel = "i"
                    }
                } else if value == 0x05D5, endsWithVowel(out, "ou") {
                    consonant = ""
                }
            }

            out += consonant
            out += vowel

            previousHadSheva = hadSheva
            previousNikud = nikud
            // Long vowels keep a following sheva vocal: tsere, holam, and
            // qamats gadol (qatan — before a sheva-letter — is short).
            previousVowelLong =
                nikud == 0x05B5 || nikud == 0x05B9
                || (nikud == 0x05B8 && !nextBaseHasSheva(j, scalars))
            atWordStart = false
            i = j
        }
        return out
    }

    private static func endsWithVowel(_ string: String, _ set: String) -> Bool {
        guard let last = string.last else { return false }
        return set.contains(last)
    }

    /// Letter state for niqqud resolution.
    private struct NikudContext {
        let atWordStart: Bool
        let previousHadSheva: Bool
        let previousVowelLong: Bool
        let hasDagesh: Bool
        let isBegadkefat: Bool
        let nextBaseIndex: Int
        let scalars: [Unicode.Scalar]
    }

    /// Resolves the niqqud point into its vowel sound + whether it is long.
    private static func hebrewVowel(
        for nikud: UInt32?,
        context: NikudContext
    ) -> (sound: String, isLong: Bool) {
        guard let nikud else { return ("", false) }

        switch nikud {
        case 0x05B0:
            // Sheva na (vocal): word-initial, second of two consecutive
            // shevas, or under a dagesh'd non-begadkefat letter. After long
            // vowels it stays silent per modern Israeli usage.
            if context.atWordStart || context.previousHadSheva {
                return ("e", false)
            }
            if context.hasDagesh && !context.isBegadkefat {
                return ("e", false)
            }
            return ("", false)
        case 0x05B8:
            // Qamats qatan (short "o") in closed unstressed syllables;
            // otherwise long "a".
            return nextBaseHasSheva(context.nextBaseIndex, context.scalars) ? ("o", false) : ("a", true)
        case 0x05B3:
            return ("o", false)                         // hataf qamats
        case 0x05B1:
            return ("e", false)                         // hataf segol
        case 0x05B2:
            return ("a", false)                         // hataf patah
        case 0x05B4:
            return ("i", false)                         // hiriq (short unless male)
        case 0x05B5:
            return ("e", true)                          // tsere
        case 0x05B6:
            return ("e", false)                         // segol
        case 0x05B7:
            return ("a", false)                         // patah
        case 0x05B9:
            return ("o", true)                          // holam
        case 0x05BB:
            return ("u", false)                         // qubuts
        default:
            return ("", false)
        }
    }

    /// Whether the next base letter carries a sheva (for the qamats-qatan rule).
    private static func nextBaseHasSheva(_ index: Int, _ scalars: [Unicode.Scalar]) -> Bool {
        var k = index
        // Skip to the next base letter first.
        while k < scalars.count, !isHebrewBase(scalars[k].value) { k += 1 }
        guard k < scalars.count else { return false }
        // Then inspect its attached points.
        k += 1
        while k < scalars.count, isHebrewPoint(scalars[k].value) {
            if scalars[k].value == 0x05B0 { return true }
            k += 1
        }
        return false
    }

    private static func isHebrewBase(_ value: UInt32) -> Bool {
        (0x05D0...0x05EA).contains(value)
    }

    /// בגדכפת letters whose dagesh is lene (pronunciation only).
    private static func isHebrewBegadkefat(_ value: UInt32) -> Bool {
        switch value {
        case 0x05D1, 0x05D2, 0x05D3, 0x05DB, 0x05DA, 0x05E4, 0x05E3, 0x05EA:
            return true
        default:
            return false
        }
    }

    /// Niqqud, dagesh, shin/sin dots and cantillation marks.
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
