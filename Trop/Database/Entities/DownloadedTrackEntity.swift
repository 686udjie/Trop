//
//  DownloadedTrackEntity.swift
//  Trop
//
//  Created by 686udjie on 19/07/2026.
//

import Foundation
import GRDB

struct DownloadedTrackEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var artist: String
    var duration: Int
    var thumbnailUrl: String?
    var localPath: String
    var downloadedAt: Date

    static let databaseTableName = "downloaded_track"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case duration
        case thumbnailUrl = "thumbnail_url"
        case localPath = "local_path"
        case downloadedAt = "downloaded_at"
    }
}
