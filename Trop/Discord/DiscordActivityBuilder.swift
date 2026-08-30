//
//  DiscordActivityBuilder.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum DiscordActivityBuilder {
    // swiftlint:disable:next function_parameter_count
    static func build(
        song: SongItem,
        artistName: String,
        albumName: String?,
        artistThumbnail: String?,
        songTitle: String,
        startTimestamp: Int64,
        endTimestamp: Int64?,
        advancedMode: Bool,
        activityType: Int = DiscordActivity.typeListening,
        activityName: String? = nil,
        stateTemplate: String = DiscordDefaults.stateTemplate,
        detailsTemplate: String = DiscordDefaults.detailsTemplate,
        btn1Enabled: Bool = true,
        btn1Label: String = DiscordDefaults.button1Label,
        btn1Url: String = DiscordDefaults.button1UrlTemplate,
        btn2Enabled: Bool = true,
        btn2Label: String = DiscordDefaults.button2Label,
        btn2Url: String = DiscordDefaults.button2Url
    ) -> DiscordActivity {
        let state: String
        let details: String?
        let renderedBtn1Label: String?
        let renderedBtn1Url: String?
        let renderedBtn2Label: String?
        let renderedBtn2Url: String?

        if advancedMode {
            let st = stateTemplate.isEmpty ? DiscordDefaults.stateTemplate : stateTemplate
            let dt = detailsTemplate.isEmpty ? DiscordDefaults.detailsTemplate : detailsTemplate
            state = DiscordTemplateRenderer.render(
                template: st, title: songTitle, artist: artistName, album: albumName, songId: song.videoId)
            details = DiscordTemplateRenderer.render(
                template: dt, title: songTitle, artist: artistName, album: albumName, songId: song.videoId)
            let lbl1 = btn1Label.isEmpty ? DiscordDefaults.button1Label : btn1Label
            renderedBtn1Label = btn1Enabled ? DiscordTemplateRenderer.render(
                template: lbl1, title: songTitle, artist: artistName, album: albumName, songId: song.videoId) : nil
            let url1 = btn1Url.isEmpty ? DiscordDefaults.button1UrlTemplate : btn1Url
            renderedBtn1Url = btn1Enabled ? DiscordTemplateRenderer.render(
                template: url1, title: songTitle, artist: artistName, album: albumName, songId: song.videoId) : nil
            let lbl2 = btn2Label.isEmpty ? DiscordDefaults.button2Label : btn2Label
            renderedBtn2Label = btn2Enabled ? DiscordTemplateRenderer.render(
                template: lbl2, title: songTitle, artist: artistName, album: albumName, songId: song.videoId) : nil
            let url2 = btn2Url.isEmpty ? DiscordDefaults.button2Url : btn2Url
            renderedBtn2Url = btn2Enabled ? DiscordTemplateRenderer.render(
                template: url2, title: songTitle, artist: artistName, album: albumName, songId: song.videoId) : nil
        } else {
            state = artistName
            details = songTitle
            renderedBtn1Label = DiscordDefaults.button1Label
            renderedBtn1Url = "\(DiscordDefaults.youtubeWatchUrl)\(song.videoId)"
            renderedBtn2Label = DiscordDefaults.button2Label
            renderedBtn2Url = DiscordDefaults.button2Url
        }

        let renderedName: String?
        if advancedMode, let name = activityName, !name.isEmpty {
            renderedName = DiscordTemplateRenderer.render(
                template: name, title: songTitle, artist: artistName, album: albumName, songId: song.videoId)
        } else {
            renderedName = activityName?.isEmpty == false ? activityName : artistName
        }

        return DiscordActivity(
            activityType: activityType,
            name: renderedName,
            state: state,
            details: details,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            largeImage: song.thumbnailUrl,
            largeText: albumName,
            smallImage: artistThumbnail,
            smallText: artistName,
            button1Label: renderedBtn1Label,
            button1Url: renderedBtn1Url,
            button2Label: renderedBtn2Label,
            button2Url: renderedBtn2Url
        )
    }
}
