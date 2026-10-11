//
//  CanvasRepository.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import Foundation
import Network

/// Serialised canvas lookups with a small settled-answer cache.
actor CanvasRepository {
    static let shared = CanvasRepository()

    private static let cacheSize = 64

    private struct Entry {
        let clip: CanvasClip?
        let withAlbum: Bool

        func reusable(nowWithAlbum: Bool) -> Bool {
            clip != nil || withAlbum || !nowWithAlbum
        }
    }

    private var cache: [String: Entry] = [:]
    private var keyOrder: [String] = []
    private var inFlight: [String: Task<CanvasClip?, Never>] = [:]

    /// The canvas for the playing track, or nil. Never throws.
    func canvasFor(videoId: String, title: String, artist: String, album: String?) async -> CanvasClip? {
        let cleanTitle = CanvasText.cleanedTrack(title)
        let cleanArtist = CanvasText.cleanedTrack(artist)
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else { return nil }
        guard await CanvasConnectivity.shared.allowsLookup() else { return cachedClip(videoId: videoId) }

        let key = cacheKey(videoId: videoId)
        if let entry = cache[key], entry.reusable(nowWithAlbum: album != nil) {
            return entry.clip
        }
        let lookup: Task<CanvasClip?, Never>
        if let existing = inFlight[key] {
            lookup = existing
        } else {
            lookup = Task {
                await SpotifyCanvas.search(title: cleanTitle, artist: cleanArtist, album: album)
            }
            inFlight[key] = lookup
        }
        let clip = await lookup.value
        inFlight[key] = nil
        let accepted: Bool = {
            guard let clip else { return false }
            return SpotifyCanvas.isMatch(
                gotName: clip.title,
                gotArtists: CanvasText.splitArtists(clip.artist),
                wantName: cleanTitle,
                wantArtist: cleanArtist
            )
        }()
        let settled = accepted ? clip : nil
        store(key: key, entry: Entry(clip: settled, withAlbum: album != nil))
        return settled
    }

    func cachedClip(videoId: String) -> CanvasClip? {
        clip(forKey: cacheKey(videoId: videoId))
    }

    func clear() {
        cache = [:]
        keyOrder = []
    }

    private func cacheKey(videoId: String) -> String {
        "song|\(videoId)"
    }

    private func store(key: String, entry: Entry) {
        cache[key] = entry
        keyOrder.removeAll { $0 == key }
        keyOrder.append(key)
        while keyOrder.count > Self.cacheSize, let eldest = keyOrder.first {
            keyOrder.removeFirst()
            cache.removeValue(forKey: eldest)
        }
    }

    private func clip(forKey key: String) -> CanvasClip? {
        cache[key]?.clip
    }
}

// MARK: - Prefetch

enum CanvasPrefetch {
    static func request(videoId: String, title: String, artist: String, album: String?) {
        Task {
            guard let clip = await CanvasRepository.shared.canvasFor(
                videoId: videoId, title: title, artist: artist, album: album
            ) else { return }
            await MainActor.run {
                guard NowPlaying.shared.videoId == videoId, SettingsStore.shared.canvasEnabled else { return }
                CanvasPlayerPreloader.shared.preload(url: clip.url)
            }
        }
    }
}

// MARK: - Connectivity guard

actor CanvasConnectivity {
    static let shared = CanvasConnectivity()

    private let monitor = NWPathMonitor()
    private var isExpensive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.setExpensive(path.isExpensive) }
        }
        monitor.start(queue: DispatchQueue(label: "app.trop.canvasConnectivity"))
    }

    func allowsLookup() async -> Bool {
        if SettingsStore.shared.canvasOverCellular { return true }
        return !isExpensive
    }

    private func setExpensive(_ value: Bool) {
        isExpensive = value
    }
}
