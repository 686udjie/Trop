//
//  LyricsRomanizer.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Lightweight script transliteration
enum LyricsRomanizer {
    static func romanize(_ text: String) -> String? {
        switch detectScript(text) {
        case .kana: return romanizeJapanese(text)
        case .hangul: return romanizeKorean(text)
        case .han: return romanizeChinese(text)
        case .devanagari: return romanizeDevanagari(text)
        case .greek: return romanizeGreek(text)
        case .cyrillic: return romanizeCyrillic(text)
        case .thai: return romanizeThai(text)
        case .hebrew: return romanizeHebrew(text)
        case .arabic: return romanizeArabic(text)
        case .georgian: return romanizeGeorgian(text)
        case .armenian: return romanizeArmenian(text)
        case nil: return nil
        }
    }

    /// Shared phoneme buffer entry: emitted text plus whether it carries a
    /// vowel sound.
    typealias Phoneme = (text: String, isVowel: Bool)

    /// Interleaves an epenthetic vowel between adjacent consonant phonemes
    /// so unvowelled words stay pronounceable (Arabic mrhba → marhaba,
    /// Hebrew mshchr → meshecher).
    static func insertEpenthetic(
        in phonemes: [Phoneme],
        vowel: String,
        startsWord: [Bool] = []
    ) -> [Phoneme] {
        var fixed: [Phoneme] = []
        for (index, phoneme) in phonemes.enumerated() {
            let beginsWord = index < startsWord.count ? startsWord[index] : false
            if index > 0,
               !beginsWord,
               !phonemes[index - 1].isVowel,
               !phoneme.isVowel,
               !phonemes[index - 1].text.isEmpty,
               !phoneme.text.isEmpty {
                fixed.append((vowel, true))
            }
            fixed.append(phoneme)
        }
        return fixed
    }

    // MARK: - Detection

    private enum Script {
        case kana, hangul, han, devanagari, greek, cyrillic, thai, hebrew, arabic, georgian, armenian
    }

    private static func detectScript(_ text: String) -> Script? {
        var best: Script?
        var bestRank = 0
        // Kana wins over han so Japanese lines stay Japanese.
        func consider(_ script: Script, rank: Int) {
            if rank > bestRank {
                bestRank = rank
                best = script
            }
        }
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                consider(.kana, rank: 50)
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
                consider(.hangul, rank: 40)
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                consider(.han, rank: 30)
            case 0x0900...0x097F:
                consider(.devanagari, rank: 28)
            case 0x0370...0x03FF, 0x1F00...0x1FFF:
                consider(.greek, rank: 26)
            case 0x0400...0x04FF:
                consider(.cyrillic, rank: 20)
            case 0x0E00...0x0E7F:
                consider(.thai, rank: 18)
            case 0x0590...0x05FF:
                consider(.hebrew, rank: 14)
            case 0x0600...0x06FF, 0x0750...0x077F:
                consider(.arabic, rank: 12)
            case 0x10A0...0x10FF, 0x1C90...0x1CBF:
                consider(.georgian, rank: 10)
            case 0x0530...0x058F:
                consider(.armenian, rank: 8)
            default:
                continue
            }
        }
        return best
    }
}
