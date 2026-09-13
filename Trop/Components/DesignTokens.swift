//
//  DesignTokens.swift
//  Trop
//
//  Created by 686udjie on 13/09/2026.
//

import SwiftUI

/// Centralized layout constants. New shared components read from here
/// instead of re-typing literals; legacy screens adopt them opportunistically.
enum DesignTokens {
    // MARK: - Spacing

    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let cardInnerSpacing: CGFloat = 4
    static let menuRowSpacing: CGFloat = 14

    // MARK: - Padding

    static let screenHPadding: CGFloat = 16
    static let rowVPadding: CGFloat = 6

    // MARK: - Corner radii

    static let thumbRadius: CGFloat = 4
    static let cardRadius: CGFloat = 8
    static let tileRadius: CGFloat = 12
    static let sheetRadius: CGFloat = 16

    // MARK: - Sizes

    static let thumbSmall: CGFloat = 40
    static let thumbMedium: CGFloat = 48
    static let heroArtwork: CGFloat = 200
}
