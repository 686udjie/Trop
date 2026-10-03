//
//  RadioOptions.swift
//  Trop
//
//  Created by 686udjie on 26/09/2026.
//

import Foundation

enum RadioStyle: String, CaseIterable, Identifiable {
    case similar
    case variety
    case deepCuts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .similar: return "Similar"
        case .variety: return "Variety"
        case .deepCuts: return "Deep Cuts"
        }
    }

    var description: String {
        switch self {
        case .similar: return "Closest matches to this song"
        case .variety: return "Wider mix around this song"
        case .deepCuts: return "Lesser-known related tracks"
        }
    }
}

struct RadioOptions {
    var style: RadioStyle = .similar
    var limit: Int = 25
    var allowExplicit: Bool = true

    static let `default` = RadioOptions()
}

extension RadioOptions {
    static var saved: RadioOptions {
        let settings = SettingsStore.shared
        return RadioOptions(
            style: settings.lastRadioStyle,
            limit: settings.lastRadioLimit,
            allowExplicit: settings.lastRadioAllowExplicit
        )
    }

    func save() {
        let settings = SettingsStore.shared
        settings.lastRadioStyle = style
        settings.lastRadioLimit = limit
        settings.lastRadioAllowExplicit = allowExplicit
    }
}
