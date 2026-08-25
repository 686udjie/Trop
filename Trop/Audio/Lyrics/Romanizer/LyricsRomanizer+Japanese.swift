//
//  LyricsRomanizer+Japanese.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Hepburn-style kana → romaji.
extension LyricsRomanizer {
    static func romanizeJapanese(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var lastVowel: Character?
        var i = 0

        func appendReading(_ romaji: String) {
            out += romaji
            if let v = romaji.last, "aeiou".contains(v) {
                lastVowel = v
            }
        }

        while i < chars.count {
            let raw = chars[i]

            // Long-vowel mark extends the previous vowel.
            if raw == "ー" {
                if let v = lastVowel { out.append(v) }
                i += 1
                continue
            }

            // Sokuon doubles the next consonant (one extra copy — the
            // following reading supplies its own).
            if raw == "っ" || katakanaToHiragana(raw) == "っ" {
                if let next = reading(in: chars, at: i + 1), let first = next.romaji.first {
                    appendReading(String(first))
                }
                i += 1
                continue
            }

            if let r = reading(in: chars, at: i) {
                appendReading(r.romaji)
                i += r.length
                continue
            }

            out.append(raw)
            if let v = raw.lowercased().last, "aeiou".contains(v) {
                lastVowel = v
            }
            i += 1
        }
        return out
    }

    private static let hiraganaReadings: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "wi", "ゑ": "we", "を": "wo", "ん": "n",
        "ゔ": "vu",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o"
    ]

    private static let digraphReadings: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo",
        "てぃ": "ti", "でぃ": "di", "とぅ": "tu",
        "うぇ": "we", "うぃ": "wi", "うぉ": "wo", "いぇ": "ye",
        "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
        "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo"
    ]

    /// Maps a katakana character onto its hiragana counterpart (same gojūon grid).
    private static func katakanaToHiragana(_ c: Character) -> Character? {
        guard let scalar = c.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x30A1...0x30F6:
            return Character(Unicode.Scalar(scalar.value - 0x60)!)
        default:
            return nil
        }
    }

    private static func reading(in chars: [Character], at index: Int) -> (romaji: String, length: Int)? {
        guard index < chars.count else { return nil }
        let normalized = chars.map { katakanaToHiragana($0) ?? $0 }
        if index + 1 < normalized.count {
            let pair = String(normalized[index]) + String(normalized[index + 1])
            if let digraph = digraphReadings[pair] {
                return (digraph, 2)
            }
        }
        if let single = hiraganaReadings[normalized[index]] {
            return (single, 1)
        }
        return nil
    }
}
