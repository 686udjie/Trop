//
//  LyricsRomanizer+Greek.swift
//  Trop
//
//  Created by 686udjie on 24/08/2026.
//

import Foundation

/// Greek → Latin (modern), with common digraphs and accented formms
extension LyricsRomanizer {
    static func romanizeGreek(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        var atWordStart = true

        while i < scalars.count {
            let char = Character(scalars[i])
            let lower = char.lowercased()
            let isLetter = greekMap[lower] != nil

            // Common digraphs first.
            if i + 1 < scalars.count {
                let pair = lower + String(Character(scalars[i + 1])).lowercased()
                switch pair {
                case "ου":
                    out += char.isUppercase ? "OU" : "ou"
                    atWordStart = false
                    i += 2
                    continue
                case "αυ":
                    out += char.isUppercase ? "Av" : "av"
                    atWordStart = false
                    i += 2
                    continue
                case "ευ":
                    out += char.isUppercase ? "Ev" : "ev"
                    atWordStart = false
                    i += 2
                    continue
                case "μπ":
                    out += char.isUppercase ? "B" : "b"
                    atWordStart = false
                    i += 2
                    continue
                case "ντ":
                    out += char.isUppercase ? "D" : "d"
                    atWordStart = false
                    i += 2
                    continue
                case "γγ":
                    // Double gamma is always the nasal [ŋɡ].
                    out += char.isUppercase ? "Ng" : "ng"
                    atWordStart = false
                    i += 2
                    continue
                case "γκ":
                    // Hard g word-initially, nasal cluster medially.
                    out += char.isUppercase
                        ? (atWordStart ? "G" : "Ng")
                        : (atWordStart ? "g" : "ng")
                    atWordStart = false
                    i += 2
                    continue
                case "γχ":
                    out += char.isUppercase ? "Nch" : "nch"
                    atWordStart = false
                    i += 2
                    continue
                case "γξ":
                    out += char.isUppercase ? "Nx" : "nx"
                    atWordStart = false
                    i += 2
                    continue
                default:
                    break
                }
            }

            if let mapped = greekMap[lower] {
                out += char.isUppercase ? mapped.capitalized : mapped
            } else {
                out.append(char)
            }
            atWordStart = !isLetter
            i += 1
        }
        return out
    }

    private static let greekMap: [String: String] = [
        "α": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "ζ": "z",
        "η": "i", "θ": "th", "ι": "i", "κ": "k", "λ": "l", "μ": "m",
        "ν": "n", "ξ": "x", "ο": "o", "π": "p", "ρ": "r", "σ": "s",
        "ς": "s", "τ": "t", "υ": "i", "φ": "f", "χ": "ch", "ψ": "ps",
        "ω": "o",
        // Accented / diaeresis forms
        "ά": "a", "έ": "e", "ή": "i", "ί": "i", "ό": "o", "ύ": "i",
        "ώ": "o", "ϊ": "i", "ϋ": "i", "ΐ": "i", "ΰ": "i"
    ]
}
