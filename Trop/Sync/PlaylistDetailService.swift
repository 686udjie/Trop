//
// PlaylistDetailService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor PlaylistDetailService {
    nonisolated static let shared = PlaylistDetailService()
    private let innerTube = InnerTubeClient.tropShared
    private let db = DatabaseService.shared

    func fetchPlaylist(playlistId: String, maxPages: Int = 100) async throws -> Int {
        let browseId = "VL\(playlistId)"
        var allItems: [[String: Any]] = []
        var token: String?
        var seenTokens = Set<String>()
        var pages = 0
        var hadShelf = false
        repeat {
            let json = try await innerTube.browse(browseId: browseId, continuation: token)
            if let items = extractPlaylistItems(from: json) {
                hadShelf = true
                allItems += items
            }
            token = extractPlaylistContinuation(from: json)
            pages += 1
            if let token, !seenTokens.insert(token).inserted {
                Log.sync.error("fetchPlaylist \(playlistId): repeated continuation token, stopping")
                break
            }
            if pages >= maxPages {
                Log.sync.error("fetchPlaylist \(playlistId): hit \(maxPages)-page cap, stopping")
                break
            }
        } while token != nil

        guard hadShelf else {
            throw InnerTubeError.invalidResponse
        }

        let snapshot = allItems
        try await db.write { db in
            let existing = try PlaylistEntity.fetchOne(db, key: playlistId)
            let entity = PlaylistEntity.merging(
                existing: existing,
                id: playlistId,
                browseId: browseId,
                name: "Playlist",
                remoteSongCount: snapshot.count
            )
            try entity.save(db)

            // Clear existing song mappings and re-insert
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ?", arguments: [playlistId])
            var skipped = 0
            for (index, rawItem) in snapshot.enumerated() {
                guard let renderer = rawItem["musicResponsiveListItemRenderer"] as? [String: Any],
                      let videoId = Self.playlistRowVideoId(renderer) else {
                    skipped += 1
                    if skipped <= 3 {
                        Log.sync.debug("fetchPlaylist \(playlistId): skipping row \(index), keys=\(rawItem.keys.sorted())")
                    }
                    continue
                }
                let nav = renderer["navigationEndpoint"] as? [String: Any]
                let watch = nav?["watchEndpoint"] as? [String: Any]
                let setVideoId = watch?["playlistSetVideoId"] as? String

                if let songItem = SongItem.from(renderer) {
                    let existing = try SongEntity.fetchOne(db, key: videoId)
                    let entity = SongEntity.merging(
                        existing: existing,
                        id: videoId,
                        title: songItem.title,
                        artistName: songItem.artists.first?.name,
                        albumName: songItem.album,
                        duration: songItem.duration,
                        thumbnailUrl: songItem.thumbnailUrl
                    )
                    try entity.save(db)
                }

                let map = PlaylistSongMap(
                    id: nil,
                    playlistId: playlistId,
                    songId: videoId,
                    position: index,
                    setVideoId: setVideoId
                )
                try map.insert(db, onConflict: .ignore)
            }
            if skipped > 0 {
                Log.sync.debug("fetchPlaylist \(playlistId): skipped \(skipped)/\(snapshot.count) rows without video id")
            }
        }
        return allItems.count
    }

    private static func playlistRowVideoId(_ renderer: [String: Any]) -> String? {
        if let videoId = renderer["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let itemData = renderer["playlistItemData"] as? [String: Any],
           let videoId = itemData["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let nav = renderer["navigationEndpoint"] as? [String: Any],
           let watch = nav["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let overlay = renderer["overlay"] as? [String: Any],
           let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = overlayRenderer["content"] as? [String: Any],
           let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
           let nav = playButton["playNavigationEndpoint"] as? [String: Any],
           let watch = nav["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        return nil
    }

    private func extractPlaylistItems(from json: [String: Any]) -> [[String: Any]]? {
        if let firstSection = BrowseLens.firstBrowseSection(json),
           let shelf = (firstSection["musicPlaylistShelfRenderer"] as? [String: Any])
            ?? (firstSection["musicShelfRenderer"] as? [String: Any]),
           let items = shelf["contents"] as? [[String: Any]] {
            return items
        }
        let twoColumnItems = twoColumnShelves(from: json).compactMap { $0["contents"] as? [[String: Any]] }.flatMap { $0 }
        if !twoColumnItems.isEmpty {
            return twoColumnItems
        }
        if let continuationContents = json["continuationContents"] as? [String: Any],
           let shelf = (continuationContents["musicPlaylistShelfContinuation"] as? [String: Any])
            ?? (continuationContents["musicShelfContinuation"] as? [String: Any]),
           let items = shelf["contents"] as? [[String: Any]] {
            return items
        }
        Log.sync.debug("extractPlaylistItems: no shelf found, top keys=\(json.keys.sorted())")
        if let contents = json["contents"] as? [String: Any] {
            Log.sync.debug("extractPlaylistItems: contents keys=\(contents.keys.sorted())")
        }
        return nil
    }

    private func extractPlaylistContinuation(from json: [String: Any]) -> String? {
        if let firstSection = BrowseLens.firstBrowseSection(json),
           let shelf = (firstSection["musicPlaylistShelfRenderer"] as? [String: Any])
            ?? (firstSection["musicShelfRenderer"] as? [String: Any]),
           let token = InnerTubeDecode.continuationToken(in: shelf) {
            return token
        }
        for shelf in twoColumnShelves(from: json) {
            if let token = InnerTubeDecode.continuationToken(in: shelf) {
                return token
            }
        }
        if let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let secondary = twoCol["secondaryContents"] as? [String: Any],
           let sectionList = secondary["sectionListRenderer"] as? [String: Any],
           let continuations = sectionList["continuations"] as? [[String: Any]],
           let first = continuations.first,
           let next = first["nextContinuationData"] as? [String: Any],
           let token = next["continuation"] as? String {
            return token
        }
        if let continuationContents = json["continuationContents"] as? [String: Any],
           let shelf = (continuationContents["musicPlaylistShelfContinuation"] as? [String: Any])
            ?? (continuationContents["musicShelfContinuation"] as? [String: Any]),
           let token = InnerTubeDecode.continuationToken(in: shelf) {
            return token
        }
        return nil
    }

    /// Every song shelf from a twoColumnBrowseResultsRenderer response
    /// (secondaryContents → sectionListRenderer), unwrapping
    /// itemSectionRenderer wrappers like the detail parser does.
    private func twoColumnShelves(from json: [String: Any]) -> [[String: Any]] {
        guard let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let secondary = twoCol["secondaryContents"] as? [String: Any],
              let sectionList = secondary["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else { return [] }
        var shelves: [[String: Any]] = []
        for section in sections {
            let unwrapped = (section["itemSectionRenderer"] as? [String: Any])
                .flatMap { ($0["contents"] as? [[String: Any]])?.first }
                ?? section
            if let shelf = (unwrapped["musicPlaylistShelfRenderer"] as? [String: Any])
                ?? (unwrapped["musicShelfRenderer"] as? [String: Any]) {
                shelves.append(shelf)
            }
        }
        return shelves
    }
}
