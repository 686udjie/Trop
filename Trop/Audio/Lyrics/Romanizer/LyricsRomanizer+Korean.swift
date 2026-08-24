//
//  LyricsRomanizer+Korean.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Hangul → Revised Romanization via jamo decomposition.
extension LyricsRomanizer {
    static func romanizeKorean(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            guard (0xAC00...0xD7A3).contains(scalar.value) else {
                out.unicodeScalars.append(scalar)
                continue
            }
            let index = Int(scalar.value - 0xAC00)
            let cho = index / (21 * 28)
            let jung = (index % (21 * 28)) / 28
            let jong = index % 28
            guard cho < choseong.count, jung < jungseong.count, jong < jongseong.count else { continue }
            out += choseong[cho] + jungseong[jung] + jongseong[jong]
        }
        return out
    }

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
