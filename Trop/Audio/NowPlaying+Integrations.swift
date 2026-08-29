//
//  NowPlaying+Integrations.swift
//  Trop
//

import Foundation

extension NowPlaying {
    func notifyIntegrationsTrackChanged() {
        let track = integrationTrackSnapshot()
        LastFMScrobbler.shared.handleTrackChange(track)
        DiscordRpcManager.shared.setActivity(
            videoId: track.videoId,
            title: track.title,
            artist: track.artist,
            album: track.album,
            isPlaying: isPlaying
        )
    }

    func notifyIntegrationsProgress() {
        var track = integrationTrackSnapshot()
        track.currentTime = currentTime
        LastFMScrobbler.shared.considerScrobble(track)
        DiscordRpcManager.shared.setActivity(
            videoId: track.videoId,
            title: track.title,
            artist: track.artist,
            album: track.album,
            isPlaying: isPlaying
        )
    }

    private func integrationTrackSnapshot() -> LastFMTrackSnapshot {
        let artist = displayArtist.isEmpty ? self.artist : displayArtist
        let album = albumTitle.isEmpty ? nil : albumTitle
        return LastFMTrackSnapshot(
            videoId: videoId,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
    }
}
