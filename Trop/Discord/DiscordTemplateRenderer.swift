//
//  DiscordTemplateRenderer.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum DiscordTemplateRenderer {
    static let placeholders = ["{song.name}", "{artist.name}", "{album.name}", "{song.id}"]

    static func render(template: String, title: String, artist: String, album: String?, songId: String = "") -> String {
        var result = template
        result = result.replacingOccurrences(of: "{song.name}", with: title)
        result = result.replacingOccurrences(of: "{song.id}", with: songId)
        result = result.replacingOccurrences(of: "{artist.name}", with: artist)
        result = result.replacingOccurrences(of: "{album.name}", with: album ?? DiscordDefaults.unknownAlbum)
        return result
    }
}
