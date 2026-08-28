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
        for song in songs where song.inLibrary != nil {
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
            let entity = try await DatabaseService.shared.fetchOne(SongEntity.self, key: videoId)
            if target {
                try await MutationService.shared.addToLibrary(
                    videoId: videoId,
                    addToken: entity?.libraryAddToken ?? ""
                )
            } else {
                try await MutationService.shared.removeFromLibrary(
                    videoId: videoId,
                    removeToken: entity?.libraryRemoveToken ?? ""
                )
            }
        } catch {
            var reverted = liked
            reverted[videoId] = !target
            liked = reverted
        }
    }
}
