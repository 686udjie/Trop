//
//  LyricsRomanizer+Korean.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Hangul → Revised Romanization via jamo decomposition, including
/// standalone compatibility jamo (ㄱ ㅏ …).
extension LyricsRomanizer {
    static func romanizeKorean(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let value = scalar.value

            // Precomposed syllables.
            if (0xAC00...0xD7A3).contains(value) {
                let index = Int(value - 0xAC00)
                let cho = index / (21 * 28)
                let jung = (index % (21 * 28)) / 28
                let jong = index % 28
                guard cho < choseong.count, jung < jungseong.count, jong < jongseong.count else { continue }
                out += choseong[cho] + jungseong[jung] + jongseong[jong]
                continue
            }

            // Standalone compatibility jamo.
            if let jamo = compatibilityJamo[value] {
                out += jamo
                continue
            }

            out.unicodeScalars.append(scalar)
        }
        return out
    }

    private static let compatibilityJamo: [UInt32: String] = [
        0x3131: "g", 0x3132: "kk", 0x3133: "ks", 0x3134: "n", 0x3135: "nj",
        0x3136: "nh", 0x3137: "d", 0x3138: "tt", 0x3139: "r", 0x313A: "rk",
        0x313B: "rm", 0x313C: "rb", 0x313D: "rs", 0x313E: "rs", 0x313F: "rp",
        0x3140: "rh", 0x3141: "m", 0x3142: "b", 0x3143: "pp", 0x3144: "bs",
        0x3145: "s", 0x3146: "ss", 0x3147: "", 0x3148: "j", 0x3149: "jj",
        0x314A: "ch", 0x314B: "k", 0x314C: "t", 0x314D: "p", 0x314E: "h",
        0x314F: "a", 0x3150: "ae", 0x3151: "ya", 0x3152: "yae", 0x3153: "eo",
        0x3154: "e", 0x3155: "yeo", 0x3156: "ye", 0x3157: "o", 0x3158: "wa",
        0x3159: "wae", 0x315A: "oe", 0x315B: "yo", 0x315C: "u", 0x315D: "wo",
        0x315E: "we", 0x315F: "wi", 0x3160: "yu", 0x3161: "eu", 0x3162: "ui",
        0x3163: "i"
    ]

    private static let choseong = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    private static let jungseong = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae",
        "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "yi", "i"
    ]
    private static let jongseong = [
        "",                                            // no final
        "k",                                           // ㄱ
        "k",                                           // ㄲ
        "k",                                           // ㄳ
        "n",                                           // ㄴ
        "n",                                           // ㄵ
        "n",                                           // ㄶ
        "t",                                           // ㄷ
        "l",                                           // ㄹ
        "k",                                           // ㄺ
        "m",                                           // ㄻ
        "p",                                           // ㄼ
        "l",                                           // ㄽ
        "l",                                           // ㄾ
        "p",                                           // ㄿ
        "l",                                           // ㅀ
        "m",                                           // ㅁ
        "p",                                           // ㅂ
        "t",                                           // ㅄ
        "t",                                           // ㅅ
        "ss",                                          // ㅆ
        "ng",                                          // ㅇ
        "t",                                           // ㅈ
        "t",                                           // ㅊ
        "k",                                           // ㅋ
        "t",                                           // ㅌ
        "p",                                           // ㅍ
        "t"                                            // ㅎ
    ]
}
