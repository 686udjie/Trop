//
//  LikeStore.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import Combine
import Foundation
import GRDB

@MainActor
class LikeStore: ObservableObject {
    static let shared = LikeStore()

    @Published private(set) var liked: [String: Bool] = [:]

    private init() {
        Task { await refresh() }
    }

    func isLiked(videoId: String) -> Bool {
        liked[videoId] ?? false
    }

    func refresh() async {
        let songs = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
        var dict: [String: Bool] = [:]
        for song in songs where song.liked {
            dict[song.id] = true
        }
        liked = dict
    }

    func toggle(song: SongItem) async {
        let videoId = song.videoId
        let target = !isLiked(videoId: videoId)

        var updated = liked
        updated[videoId] = target
        liked = updated

        do {
            if target {
                try await MutationService.shared.likeSong(videoId: videoId)
                if SettingsStore.shared.autoDownloadOnLike {
                    await DownloadManager.shared.download(song: song)
                }
            } else {
                try await MutationService.shared.unlikeSong(videoId: videoId)
            }
            let artist = song.artists.map(\.name).joined(separator: ", ")
            let track = song.title
            if !artist.isEmpty, !track.isEmpty {
                Task { await LastFMIntegration.shared.handleLove(artist: artist, track: track, love: target) }
            }
        } catch {
            var reverted = liked
            reverted[videoId] = !target
            liked = reverted
        }
    }
}
