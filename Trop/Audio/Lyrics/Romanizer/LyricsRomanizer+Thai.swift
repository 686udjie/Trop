//
//  LyricsRomanizer+Thai.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Thai → Latin, RTGS-style with syllable-aware parsing: implicit vowels,
/// initial vs final consonant forms, consonant clusters (คร ปล …), preposed
/// vowels and compounds (เ-า, เ-ีย, โ-ะ), carrier อ, and the silencing ์.
extension LyricsRomanizer {
    static func romanizeThai(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var lastConsonantRange: Range<String.Index>?
        var i = 0
        /// Previous syllable ended on an open vowel sound, so a following
        /// vowel-less consonant closes it instead of starting a new one.
        var openVowelPending = false

        func emit(_ s: String, tracked: Bool = false) {
            let start = out.endIndex
            out += s
            lastConsonantRange = tracked ? start..<out.endIndex : nil
        }

        while i < scalars.count {
            let value = scalars[i].value

            // Tone marks and diacritics carry no sound; ์ removes the
            // preceding consonant.
            if isThaiSkippable(value) {
                i += 1
                continue
            }
            if value == 0x0E4C {
                if let range = lastConsonantRange {
                    out.removeSubrange(range)
                    lastConsonantRange = nil
                }
                openVowelPending = false
                i += 1
                continue
            }
            if value == 0x0E4F { // ๆ repeats the previous word — skipped
                i += 1
                continue
            }

            // Standalone following vowel (after a finished syllable).
            if let v = thaiFollowingVowel(value) {
                emit(v)
                openVowelPending = true
                i += 1
                continue
            }

            // Preposed vowels open their syllable: consonant first, then the
            // vowel sound (ไทย → thai, เขา → khao).
            switch value {
            case 0x0E40, 0x0E41, 0x0E42, 0x0E43, 0x0E44:
                let base = thaiPreVowel(value)
                i += 1
                let (consumed, endsOpen) = emitPreposedSyllable(
                    scalars, i: i, base: base, emit: { emit($0, tracked: $1) }
                )
                openVowelPending = endsOpen
                i = consumed
                continue
            default:
                break
            }

            guard let initial = thaiInitials[value] else {
                out.unicodeScalars.append(scalars[i])
                lastConsonantRange = nil
                openVowelPending = false
                i += 1
                continue
            }

            let isCarrierO = value == 0x0E2D // อ carries vowels silently

            // Collect this consonant's vowel signs, skipping tone marks.
            var j = i + 1
            var vowel = ""
            while j < scalars.count {
                let v = scalars[j].value
                if isThaiSkippable(v) { j += 1; continue }
                if let vv = thaiFollowingVowel(v) { vowel += vv; j += 1; continue }
                break
            }

            // Locate the next significant token after the vowel.
            var k = j
            while k < scalars.count, isThaiSkippable(scalars[k].value) { k += 1 }
            let hasNextConsonant = k < scalars.count && thaiInitials[scalars[k].value] != nil
            let atEnd = k >= scalars.count || !isThaiLetterish(scalars[k].value)

            if isCarrierO {
                // อ with its own vowel is silent; alone it reads "o".
                emit(vowel.isEmpty ? "o" : vowel, tracked: true)
                openVowelPending = true
                i = j
                continue
            }

            if !vowel.isEmpty {
                if hasNextConsonant, !consonantHasOwnVowel(scalars, k + 1) {
                    // Explicit vowel + closing consonant (วัส → wat).
                    emit(initial + vowel + (thaiFinals[scalars[k].value] ?? ""), tracked: true)
                    openVowelPending = false
                    i = k + 1
                    continue
                }
                // Word-final long "i" reads "ee" (ดี → dee).
                let rendered = (atEnd && vowel == "i") ? "ee" : vowel
                emit(initial + rendered, tracked: true)
                openVowelPending = true
                i = j
                continue
            }

            // No written vowel on this consonant.
            if hasNextConsonant {
                if openVowelPending {
                    // Closes the previous open syllable (ขอบ → khop).
                    emit(thaiFinals[value] ?? "", tracked: true)
                    openVowelPending = false
                    i += 1
                    continue
                }
                if consonantHasOwnVowel(scalars, k + 1) {
                    if isThaiClusterLead(value, scalars[k].value) {
                        // Cluster lead: ครับ → kh-…
                        emit(initial, tracked: true)
                        i = k
                        continue
                    }
                    // Isolated leading syllable with implicit "a" (สวัสดี → sa-…).
                    emit(initial + "a", tracked: true)
                    openVowelPending = false
                    i = k
                    continue
                }
                // Consonant pair closing a word: implicit "o" between them
                // (ผม → phom, คน → khon). A carrier-อ second letter keeps
                // the syllable open so the next consonant closes it (ขอบ → khop).
                let secondIsCarrier = scalars[k].value == 0x0E2D
                emit(initial + "o" + (secondIsCarrier ? "" : (thaiFinals[scalars[k].value] ?? "")), tracked: true)
                openVowelPending = secondIsCarrier
                i = k + 1
                continue
            }

            // Trailing bare consonant takes its final form (ไทย → thai).
            emit(thaiFinals[value] ?? initial, tracked: true)
            openVowelPending = false
            i = j
        }
        return out
    }

    /// Emits consonant + vowel for preposed-vowel syllables, folding
    /// compounds: เ-า → ao, เ-ีย → ia, เ-C-ย → oe, โ-ะ → o.
    private static func emitPreposedSyllable(
        _ scalars: [Unicode.Scalar],
        i: Int,
        base: String,
        emit: (String, Bool) -> Void
    ) -> (Int, Bool) {
        guard i < scalars.count, let initial = thaiInitials[scalars[i].value] else {
            emit(base, false)
            return (i, true)
        }

        var j = i + 1
        var extra = ""
        while j < scalars.count {
            let v = scalars[j].value
            if isThaiSkippable(v) { j += 1; continue }
            if let vv = thaiFollowingVowel(v) { extra += vv; j += 1; continue }
            break
        }
        let tailIsSaraA = j < scalars.count && scalars[j].value == 0x0E30
        let tailIsYod = j < scalars.count && scalars[j].value == 0x0E22

        if base == "e", extra == "aa" { // เ-C-า
            emit(initial + "ao", true)
            return (j + 1, false)
        }
        if base == "e", tailIsYod {
            emit(initial + (extra.contains("i") ? "ia" : "oe"), true)
            return (j + 1, false)
        }
        if base == "o", tailIsSaraA { // โ-C-ะ
            emit(initial + "o", true)
            return (j + 1, false)
        }
        if base == "ai", tailIsYod { // ไ/ใ-C-ย: yod already inside the diphthong
            emit(initial + "ai", true)
            return (j + 1, false)
        }

        emit(initial + base + extra, true)
        return (j, true)
    }

    private static func isThaiClusterLead(_ lead: UInt32, _ follow: UInt32) -> Bool {
        let leads: Set<UInt32> = [0x0E01, 0x0E02, 0x0E03, 0x0E04, 0x0E15, 0x0E17, 0x0E1B, 0x0E1C, 0x0E1E]
        let follows: Set<UInt32> = [0x0E23, 0x0E25, 0x0E27]
        return leads.contains(lead) && follows.contains(follow)
    }

    private static func isThaiLetterish(_ value: UInt32) -> Bool {
        thaiInitials[value] != nil || thaiFollowingVowel(value) != nil || isThaiSkippable(value)
    }

    private static func isThaiSkippable(_ value: UInt32) -> Bool {
        switch value {
        case 0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E47, 0x0E4D, 0x0E3A:
            return true
        default:
            return false
        }
    }

    /// Whether the consonant at `index` carries its own vowel (sign or
    /// preposed vowel opening its syllable).
    private static func consonantHasOwnVowel(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        var k = index
        while k < scalars.count, isThaiSkippable(scalars[k].value) { k += 1 }
        guard k < scalars.count else { return false }
        let value = scalars[k].value
        return thaiFollowingVowel(value) != nil
            || value == 0x0E40 || value == 0x0E41 || value == 0x0E42
            || value == 0x0E43 || value == 0x0E44
    }

    private static func thaiFollowingVowel(_ value: UInt32) -> String? {
        switch value {
        case 0x0E30: return "a"
        case 0x0E32: return "aa"
        case 0x0E33: return "am"
        case 0x0E31: return "a"
        case 0x0E35: return "i"
        case 0x0E36: return "ue"
        case 0x0E37: return "ue"
        case 0x0E38: return "u"
        case 0x0E39: return "uu"
        default: return nil
        }
    }

    private static func thaiPreVowel(_ value: UInt32) -> String {
        switch value {
        case 0x0E40: return "e"
        case 0x0E41: return "ae"
        case 0x0E42: return "o"
        case 0x0E43, 0x0E44: return "ai"
        default: return ""
        }
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
        0x0E06: "t", 0x0E07: "t", 0x0E08: "t", 0x0E09: "t", 0x0E0A: "t",
        0x0E0B: "t", 0x0E0C: "t", 0x0E0D: "i", 0x0E0E: "t", 0x0E0F: "t",
        0x0E10: "t", 0x0E11: "t", 0x0E12: "t", 0x0E13: "n", 0x0E14: "t",
        0x0E15: "t", 0x0E16: "t", 0x0E17: "t", 0x0E18: "t", 0x0E19: "n",
        0x0E1A: "p", 0x0E1B: "p", 0x0E1C: "t", 0x0E1D: "t", 0x0E1E: "p",
        0x0E1F: "t", 0x0E20: "p", 0x0E21: "m", 0x0E22: "i", 0x0E23: "n",
        0x0E25: "n", 0x0E26: "n", 0x0E27: "o", 0x0E28: "t", 0x0E29: "t",
        0x0E2A: "t", 0x0E2B: "", 0x0E2D: "", 0x0E2E: ""
    ]
}
