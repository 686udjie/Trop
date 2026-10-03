//
//  Notifications+App.swift
//  Trop
//
//  Created by 686udjie on 13/09/2026.
//

import Foundation

extension Notification.Name {
    // durationDidUpdate comes from SwiftyTube's DurationCache.
    static let personalizationDataUpdated = Notification.Name("personalizationDataUpdated")
    static let nowPlayingDidChange = Notification.Name("nowPlayingDidChange")
    static let lastFMLikeChanged = Notification.Name("lastFMLikeChanged")
}
