//
//  LyricsRomanizer+Chinese.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Han → Hanyu Pinyin with tone marks 
extension LyricsRomanizer {
    /// System Mandarin→Latin transform: 我爱你 → wǒ ài nǐ
    static func romanizeChinese(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        return mutable as String
    }
}
