//
//  SearchHistoryEntity.swift
//  Trop
//
//  Created by 686udjie on 04/07/2026.
//

import Foundation

struct SearchHistoryEntity: Codable, Hashable {
    var query: String
    var timestamp: Date
}
