//
//  PodcastEntity.swift
//  Trop
//
//  Created by 686udjie on 05/07/2026.
//

import Foundation
import GRDB

struct PodcastEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var thumbnailUrl: String?
    var subscribedAt: Date?

    static let databaseTableName = "podcast"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case thumbnailUrl = "thumbnail_url"
        case subscribedAt = "subscribed_at"
    }
}
