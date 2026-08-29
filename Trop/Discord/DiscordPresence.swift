//
//  DiscordPresence.swift
//  Trop
//

import Foundation

enum DiscordActivityType: Int {
    case playing = 0
    case streaming = 1
    case listening = 2
    case watching = 3
    case competing = 5
}

enum DiscordPresenceStatus: String {
    case online
    case idle
    case dnd
    case invisible
}

struct DiscordActivityPayload: Equatable {
    var name: String
    var type: Int
    var details: String?
    var state: String?
    var largeImage: String?
    var largeText: String?
    var smallImage: String?
    var smallText: String?
    var startMs: Int64?
    var endMs: Int64?
    var buttons: [(label: String, url: String)]

    static func == (lhs: DiscordActivityPayload, rhs: DiscordActivityPayload) -> Bool {
        lhs.name == rhs.name
            && lhs.type == rhs.type
            && lhs.details == rhs.details
            && lhs.state == rhs.state
            && lhs.largeImage == rhs.largeImage
            && lhs.largeText == rhs.largeText
            && lhs.smallImage == rhs.smallImage
            && lhs.smallText == rhs.smallText
            && lhs.startMs == rhs.startMs
            && lhs.endMs == rhs.endMs
            && lhs.buttons.map(\.label) == rhs.buttons.map(\.label)
            && lhs.buttons.map(\.url) == rhs.buttons.map(\.url)
    }
}

enum DiscordPresence {
    static func buildActivity(
        name: String,
        type: DiscordActivityType = .listening,
        details: String? = nil,
        state: String? = nil,
        largeImage: String? = nil,
        largeText: String? = nil,
        startMs: Int64? = nil,
        buttons: [(String, String)] = []
    ) -> DiscordActivityPayload {
        DiscordActivityPayload(
            name: name,
            type: type.rawValue,
            details: details,
            state: state,
            largeImage: largeImage,
            largeText: largeText,
            smallImage: nil,
            smallText: nil,
            startMs: startMs,
            endMs: nil,
            buttons: buttons.map { (label: $0.0, url: $0.1) }
        )
    }

    static func buildPresenceUpdateJSON(
        status: DiscordPresenceStatus,
        activities: [DiscordActivityPayload],
        afk: Bool = false
    ) -> [String: Any] {
        let activityObjects: [[String: Any]] = activities.map { activityToDict($0) }
        return [
            "op": 3,
            "d": [
                "since": NSNull(),
                "activities": activityObjects,
                "status": status.rawValue,
                "afk": afk
            ] as [String: Any]
        ]
    }

    private static func activityToDict(_ activity: DiscordActivityPayload) -> [String: Any] {
        var obj: [String: Any] = [
            "name": activity.name.isEmpty ? "Trop" : activity.name,
            "type": activity.type
        ]
        if let details = activity.details, !details.isEmpty {
            obj["details"] = String(details.prefix(128))
        }
        if let state = activity.state, !state.isEmpty {
            obj["state"] = String(state.prefix(128))
        }
        if let startMs = activity.startMs {
            var timestamps: [String: Any] = ["start": startMs]
            if let endMs = activity.endMs {
                timestamps["end"] = endMs
            }
            obj["timestamps"] = timestamps
        }
        var assets: [String: String] = [:]
        if let largeImage = activity.largeImage, !largeImage.isEmpty {
            assets["large_image"] = largeImage
        }
        if let largeText = activity.largeText, !largeText.isEmpty {
            assets["large_text"] = String(largeText.prefix(128))
        }
        if let smallImage = activity.smallImage, !smallImage.isEmpty {
            assets["small_image"] = smallImage
        }
        if let smallText = activity.smallText, !smallText.isEmpty {
            assets["small_text"] = String(smallText.prefix(128))
        }
        if !assets.isEmpty {
            obj["assets"] = assets
        }
        if !activity.buttons.isEmpty {
            obj["buttons"] = activity.buttons.prefix(2).map(\.label)
            obj["metadata"] = [
                "button_urls": activity.buttons.prefix(2).map(\.url)
            ]
        }
        return obj
    }
}
