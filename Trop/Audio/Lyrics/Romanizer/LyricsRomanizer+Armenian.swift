//
//  LyricsRomanizer+Armenian.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Armenian → Latin, with word-initial ye-/vo- rules and the ու→u digraph
extension LyricsRomanizer {
    static func romanizeArmenian(_ text: String) -> String {
        let lowercased = text.lowercased()
        let chars = Array(lowercased)
        var out = ""
        var atWordStart = true

        for (index, char) in chars.enumerated() {
            let key = String(char)
            let isLetter = armenianMap[key] != nil

            if isLetter {
                // ե and ո take ye-/vo- only at the start of a word;
                // ու is the digraph "u".
                if key == "ո", index + 1 < chars.count, chars[index + 1] == "ւ" {
                    out += atWordStart ? "vo" : "o"
                    atWordStart = false
                    continue
                }
                if key == "ւ", out.hasSuffix("o") || out.hasSuffix("vo") {
                    out += "u"
                    atWordStart = false
                    continue
                }
                if let mapped = armenianMap[key] {
                    var result = mapped
                    if index == 0 || atWordStart {
                        if key == "ե" { result = "ye" }
                    }
                    out += result
                }
                atWordStart = false
            } else {
                out.append(char)
                atWordStart = true
            }
        }
        return out
    }

    private static let armenianMap: [String: String] = [
        "ա": "a", "բ": "b", "գ": "g", "դ": "d", "ե": "e", "զ": "z",
        "է": "e", "ը": "y", "թ": "t", "ժ": "zh", "ի": "i", "լ": "l",
        "խ": "kh", "ծ": "ts", "կ": "k", "հ": "h", "ձ": "dz", "ղ": "gh",
        "ճ": "ch", "մ": "m", "յ": "y", "ն": "n", "շ": "sh", "ո": "o",
        "չ": "ch", "պ": "p", "ջ": "j", "ռ": "r", "ս": "s", "վ": "v",
        "տ": "t", "ր": "r", "ց": "ts", "ւ": "w", "փ": "p", "ք": "q",
        "օ": "o", "ֆ": "f", "և": "yev"
    ]
}
