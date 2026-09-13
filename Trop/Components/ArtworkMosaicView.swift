//
//  ArtworkMosaicView.swift
//  Trop
//
//  Created by 686udjie on 13/09/2026.
//

import SwiftUI

/// 2x2 song-artwork mosaic used for playlist artwork, matching the Downloads
/// header. Shared by PlaylistHeaderView and the playlist detail header.
struct ArtworkMosaicView: View {
    var urls: [String]
    var size: CGFloat = 200

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 2)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(urls.prefix(4).enumerated()), id: \.offset) { _, url in
                AsyncImageView(url: url)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }
}
