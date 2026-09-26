//
//  QueueStore.swift
//  Trop
//
//  Created by 686udjie on 29/09/2026.
//

import Foundation

struct QueueStore {
    var songs: [SongItem] = []
    var index: Int = 0
    var originalSongs: [SongItem]?
    var originalIndex: Int = 0
    var isShuffleOn = false

    var hasNext: Bool { index + 1 < songs.count }
    var hasPrevious: Bool { index > 0 }

    mutating func setQueue(_ songs: [SongItem], startIndex: Int) {
        self.songs = songs
        self.index = songs.isEmpty ? 0 : min(max(startIndex, 0), songs.count - 1)
        self.originalSongs = nil
        self.isShuffleOn = false
    }

    mutating func repairIndex(currentVideoId: String?) {
        guard !songs.isEmpty else { index = 0; return }
        if let currentVideoId,
           let idx = songs.firstIndex(where: { $0.videoId == currentVideoId }) {
            index = idx
        } else {
            index = min(max(index, 0), songs.count - 1)
        }
    }

    func upcoming(prefixLimit: Int? = nil) -> [SongItem] {
        let next = index + 1
        guard songs.indices.contains(next) else { return [] }
        let rest = Array(songs[next...])
        guard let prefixLimit else { return rest }
        return Array(rest.prefix(prefixLimit))
    }

    /// Shuffles upcoming songs, keeping history + current in place.
    mutating func enableShuffle() {
        guard songs.count > 1 else { isShuffleOn = true; return }
        if originalSongs == nil {
            originalSongs = songs
            originalIndex = index
        }
        let prefix = index > 0 ? Array(songs[0..<index]) : []
        let current = songs[index]
        var rest = index + 1 < songs.count ? Array(songs[(index + 1)...]) : []
        rest.shuffle()
        songs = prefix + [current] + rest
        index = prefix.count
        isShuffleOn = true
    }

    /// Restores pre-shuffle order, keeping the current song selected even if
    /// radio appends added songs absent from the original.
    mutating func disableShuffle(currentVideoId: String?) {
        guard songs.indices.contains(index) else { return }
        if let orig = originalSongs {
            let current = currentVideoId ?? songs[index].videoId
            songs = orig
            index = orig.firstIndex(where: { $0.videoId == current }) ?? min(index, orig.count - 1)
        }
        originalSongs = nil
        isShuffleOn = false
    }

    mutating func move(from source: IndexSet, to destination: Int, currentVideoId: String?) {
        guard !source.isEmpty, songs.indices.contains(source.first ?? -1) else { return }
        // Manual move (avoids SwiftUI dependency so this stays pure/testable).
        let sorted = source.sorted()
        var moving: [SongItem] = []
        // Remove from highest index first to keep indices valid.
        var remaining = songs
        for idx in sorted.reversed() {
            moving.insert(remaining.remove(at: idx), at: 0)
        }
        var dest = destination
        // Adjust destination for removed predecessors.
        dest -= sorted.filter { $0 < destination }.count
        dest = min(max(dest, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: dest)
        songs = remaining
        repairIndex(currentVideoId: currentVideoId)
    }
}
