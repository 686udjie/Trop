//
//  PinState.swift
//  Trop
//
//  Created by 686udjie on 13/09/2026.
//

import Foundation
import Observation

/// Speed-dial pin state shared by the song and player menu sheets.
/// Consolidates the identical `isPinned` + `loadStates` + `togglePin` trios.
@Observable
final class PinState {
    var isPinned = false

    func load(videoId: String) async {
        isPinned = (try? await DatabaseService.shared.isPinnedToSpeedDial(videoId: videoId)) ?? false
    }

    func toggle(song: SongItem) async {
        let target = !isPinned
        isPinned = target
        do {
            if target {
                try await DatabaseService.shared.pinToSpeedDial(song: song)
            } else {
                try await DatabaseService.shared.removeFromSpeedDial(videoId: song.videoId)
            }
        } catch {
            isPinned = !target
        }
    }
}
