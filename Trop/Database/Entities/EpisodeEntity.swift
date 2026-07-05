//
//  EpisodeEntity.swift
//  Trop
//
//  Created by 686udjie on 05/07/2026.
//

import Foundation
import GRDB

struct EpisodeEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var duration: Int
    var thumbnailUrl: String?
    var podcastId: String?
    var podcastName: String?
    var isPlayed: Bool = false
    var savedAt: Date?

    static let databaseTableName = "episode"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case thumbnailUrl = "thumbnail_url"
        case podcastId = "podcast_id"
        case podcastName = "podcast_name"
        case isPlayed = "is_played"
        case savedAt = "saved_at"
    }
}
