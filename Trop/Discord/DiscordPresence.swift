//
//  DiscordPresence.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum ActivityType: Int {
    case playing = 0
    case streaming = 1
    case listening = 2
    case watching = 3
    case custom = 4
    case competing = 5
}

enum PresenceStatus: String {
    case online
    case idle
    case dnd
    case invisible

    var wire: String { rawValue }
}

struct ActivityPayload: Equatable {
    var name: String = ""
    var type: Int
    var details: String?
    var state: String?
    var url: String?
    var largeImage: String?
    var largeText: String?
    var smallImage: String?
    var smallText: String?
    var startMs: Int64?
    var endMs: Int64?
    var buttons: [(String, String)] = []

    static func == (lhs: ActivityPayload, rhs: ActivityPayload) -> Bool {
        lhs.name == rhs.name &&
        lhs.type == rhs.type &&
        lhs.details == rhs.details &&
        lhs.state == rhs.state &&
        lhs.url == rhs.url &&
        lhs.largeImage == rhs.largeImage &&
        lhs.largeText == rhs.largeText &&
        lhs.smallImage == rhs.smallImage &&
        lhs.smallText == rhs.smallText &&
        lhs.startMs == rhs.startMs &&
        lhs.endMs == rhs.endMs &&
        lhs.buttons.elementsEqual(rhs.buttons, by: { $0.0 == $1.0 && $0.1 == $1.1 })
    }
}

enum DiscordPresence {
    static func buildActivity(
        name: String = "",
        type: ActivityType,
        details: String? = nil,
        state: String? = nil,
        url: String? = nil,
        largeImage: String? = nil,
        largeText: String? = nil,
        smallImage: String? = nil,
        smallText: String? = nil,
        startMs: Int64? = nil,
        endMs: Int64? = nil,
        buttons: [(String, String)] = []
    ) -> ActivityPayload {
        ActivityPayload(
            name: name,
            type: type.rawValue,
            details: details,
            state: state,
            url: url,
            largeImage: largeImage,
            largeText: largeText,
            smallImage: smallImage,
            smallText: smallText,
            startMs: startMs,
            endMs: endMs,
            buttons: buttons
        )
    }

    static func buildPresenceUpdate(
        status: PresenceStatus,
        afk: Bool = false,
        since: Int64 = 0,
        activities: [ActivityPayload]
    ) -> String {
        let d: [String: Any] = [
            "since": since,
            "status": status.wire,
            "afk": afk,
            "activities": activities.map { activityToJson($0) }
        ]
        // Ensure since is number
        let root: [String: Any] = ["op": 3, "d": d]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private static func activityToJson(_ activity: ActivityPayload) -> [String: Any] {
        var obj: [String: Any] = [
            "name": activity.name,
            "type": activity.type
        ]
        if let v = activity.details { obj["details"] = v }
        if let v = activity.state { obj["state"] = v }
        if let v = activity.url { obj["url"] = v }

        if activity.startMs != nil || activity.endMs != nil {
            var ts: [String: Any] = [:]
            if let s = activity.startMs { ts["start"] = s }
            if let e = activity.endMs { ts["end"] = e }
            obj["timestamps"] = ts
        }
        if activity.largeImage != nil || activity.smallImage != nil {
            var assets: [String: Any] = [:]
            if let v = activity.largeImage { assets["large_image"] = v }
            if let v = activity.largeText { assets["large_text"] = v }
            if let v = activity.smallImage { assets["small_image"] = v }
            if let v = activity.smallText { assets["small_text"] = v }
            obj["assets"] = assets
        }
        if !activity.buttons.isEmpty {
            let labels = activity.buttons.map { $0.0 }
            let urls = activity.buttons.map { $0.1 }.filter { !$0.isEmpty }
            obj["buttons"] = labels
            if !urls.isEmpty {
                obj["metadata"] = ["button_urls": urls]
            }
        }
        return obj
    }
}
