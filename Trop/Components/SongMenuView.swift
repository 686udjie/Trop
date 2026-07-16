//
//  SongMenuView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct SongMenuView: View {
    let songItem: SongItem
    let webUrl: String
    let artistBrowseId: String?
    let albumBrowseId: String?
    let onNavigate: (DetailRoute) -> Void

    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = webUrl
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            if let artistId = artistBrowseId {
                Button {
                    onNavigate(.artist(browseId: artistId))
                } label: {
                    Label("Go to Artist", systemImage: "music.mic")
                }
            }
            if let albumId = albumBrowseId {
                Button {
                    onNavigate(.album(browseId: albumId))
                } label: {
                    Label("Go to Album", systemImage: "record.circle")
                }
            }

        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.blue)
                .rotationEffect(.degrees(90))
        }
        .menuOrder(.fixed)
    }
}
