//
//  Alignment+App.swift
//  Trop
//
//  Created by 686udjie on 13/09/2026.
//

import SwiftUI

extension Alignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}
