//
//  MediaGridCell.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI

/// Square artwork card with two-line title + optional subtitle, shared by the
/// artist albums carousel and search album carousel. `size` fixes the width
/// for carousels; nil sizes flexibly for grids.
struct MediaGridCell: View {
    var thumbnailUrl: String?
    var title: String
    var subtitle: String?
    var size: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.cardInnerSpacing) {
            AsyncImageView(url: thumbnailUrl)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: size, alignment: .leading)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: size, alignment: .leading)
            }
        }
        .frame(width: size)
    }
}

/// Large centered artwork for detail headers (album/playlist/podcast),
/// replacing the copy-pasted 200pt framed/clipped/shadowed blocks.
struct HeroArtworkView: View {
    var url: String?
    var size: CGFloat = DesignTokens.heroArtwork

    var body: some View {
        AsyncImageView(url: url)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.tileRadius))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
