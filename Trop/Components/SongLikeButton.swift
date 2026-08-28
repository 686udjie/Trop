//
//  SongLikeButton.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct SongLikeButton: View {
    let song: SongItem
    @ObservedObject private var likeStore = LikeStore.shared

    var body: some View {
        let liked = likeStore.isLiked(videoId: song.videoId)
        Button {
            Task { await likeStore.toggle(song: song) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.body)
        }
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .frame(minWidth: 32, minHeight: 44)
        .contentShape(Rectangle())
    }
}
