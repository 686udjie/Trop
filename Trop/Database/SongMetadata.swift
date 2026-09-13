//
//  SongMetadata.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import Foundation

/// Fetched song metadata used to fill skeleton entities.
struct SongMetadata {
    let title: String
    var artistName: String?
    var thumbnailUrl: String?
    var duration: Int
    var albumName: String?
}

/// Shared skeleton creation + preserve-policy merging for song enrichment.
/// Consolidates the near-identical flows in MutationService (like/library)
/// and PersonalizationService (liked songs, forgotten favorites).
enum SongEnrichment {
    static func skeleton(id: String, liked: Bool, addToken: String = "") -> SongEntity {
        SongEntity(
            id: id, title: "", artistName: nil, albumName: nil,
            duration: 0, thumbnailUrl: nil,
            liked: liked, totalPlayTime: 0, inLibrary: nil,
            libraryAddToken: addToken, libraryRemoveToken: "",
            isEpisode: false, isUploaded: false, isVideo: false,
            createDate: Date(), modifyDate: Date()
        )
    }

    /// Fills empty fields from metadata, preserving stored values
    /// (including a stored album name, which the old MutationService merge
    /// used to wipe with nil). Does not touch `modifyDate` — callers that
    /// persist set it explicitly.
    static func merging(_ entity: SongEntity, with metadata: SongMetadata) -> SongEntity {
        var enriched = entity
        if enriched.title.isEmpty {
            enriched.title = metadata.title
        }
        enriched.artistName = enriched.artistName ?? metadata.artistName
        enriched.thumbnailUrl = enriched.thumbnailUrl ?? metadata.thumbnailUrl
        if enriched.duration == 0 {
            enriched.duration = metadata.duration
        }
        enriched.albumName = enriched.albumName ?? metadata.albumName
        return enriched
    }
}
