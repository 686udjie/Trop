//
//  LyricsRomanizer+Georgian.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Georgian Mkhedruli → Latin
extension LyricsRomanizer {
    static func romanizeGeorgian(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            if let mapped = georgianMap[Character(scalar)] {
                out += mapped
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static let georgianMap: [Character: String] = [
        "ა": "a", "ბ": "b", "გ": "g", "დ": "d", "ე": "e", "ვ": "v",
        "ზ": "z", "თ": "t", "ი": "i", "კ": "k", "ლ": "l", "მ": "m",
        "ნ": "n", "ო": "o", "პ": "p", "ჟ": "zh", "რ": "r", "ს": "s",
        "ტ": "t", "უ": "u", "ფ": "p", "ქ": "k", "ღ": "gh", "ყ": "q",
        "შ": "sh", "ჩ": "ch", "ც": "ts", "ძ": "dz", "წ": "ts", "ჭ": "ch",
        "ხ": "kh", "ჯ": "j", "ჰ": "h"
    ]
}
