//
//  Equalizer.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import Foundation

/// A fixed set of 10 band center frequencies used by the equalizer.
let equalizerFrequencies: [Double] = [60, 120, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000]

/// Gain bounds in dB, matching Spotify's ±12 dB range.
let equalizerMinGain: Double = -12
let equalizerMaxGain: Double = 12

struct EqualizerPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let gains: [Double]
}

enum EqualizerPresets {
    /// The built-in presets. Gains are dB values for `equalizerFrequencies`.
    static let all: [EqualizerPreset] = [
        EqualizerPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(id: "bassBoost", name: "Bass Boost", gains: [7, 6, 4, 2, 1, 0, 0, 0, 0, 0]),
        EqualizerPreset(id: "bassReducer", name: "Bass Reducer", gains: [-7, -6, -4, -2, -1, 0, 0, 0, 0, 0]),
        EqualizerPreset(id: "trebleBoost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 6, 7]),
        EqualizerPreset(id: "trebleReducer", name: "Treble Reducer", gains: [0, 0, 0, 0, 0, -1, -2, -4, -6, -7]),
        EqualizerPreset(id: "vShape", name: "V-Shape", gains: [6, 5, 3, 1, 0, 0, 1, 3, 5, 6]),
        EqualizerPreset(id: "rock", name: "Rock", gains: [5, 4, 2, 0, -1, -1, 0, 2, 4, 5]),
        EqualizerPreset(id: "pop", name: "Pop", gains: [-1, 0, 1, 3, 3, 2, 1, 0, -1, -1]),
        EqualizerPreset(id: "hiphop", name: "Hip-Hop", gains: [6, 5, 3, 1, 0, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "electronic", name: "Electronic", gains: [5, 4, 3, 1, 0, 1, 2, 3, 4, 5]),
        EqualizerPreset(id: "jazz", name: "Jazz", gains: [3, 2, 1, 2, 1, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "classical", name: "Classical", gains: [4, 3, 2, 1, 0, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "acoustic", name: "Acoustic", gains: [4, 3, 2, 1, 0, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 1, 3, 4, 3, 1, 0, -2]),
        EqualizerPreset(id: "loudness", name: "Loudness", gains: [4, 3, 2, 1, 0, 1, 2, 3, 4, 5])
    ]

    static func preset(named id: String) -> EqualizerPreset? {
        all.first { $0.id == id }
    }
}
