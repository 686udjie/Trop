//
// FormatEntity.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct FormatEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var itag: Int
    var mimeType: String
    var codecs: String
    var bitrate: Int
    var sampleRate: Int
    var contentLength: Int64
    var loudnessDb: Double?
    var perceptualLoudnessDb: Double?
    var playbackUrl: String?

    static let databaseTableName = "format"

    enum CodingKeys: String, CodingKey {
        case id
        case itag
        case mimeType = "mime_type"
        case codecs
        case bitrate
        case sampleRate = "sample_rate"
        case contentLength = "content_length"
        case loudnessDb = "loudness_db"
        case perceptualLoudnessDb = "perceptual_loudness_db"
        case playbackUrl = "playback_url"
    }
}
