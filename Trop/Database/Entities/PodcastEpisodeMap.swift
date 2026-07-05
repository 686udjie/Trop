//
//  PodcastEpisodeMap.swift
//  Trop
//
//  Created by 686udjie on 05/07/2026.
//

import Foundation
import GRDB

struct PodcastEpisodeMap: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var podcastId: String
    var episodeId: String
    var position: Int

    static let databaseTableName = "podcast_episode_map"

    enum CodingKeys: String, CodingKey {
        case id
        case podcastId = "podcast_id"
        case episodeId = "episode_id"
        case position
    }
}
