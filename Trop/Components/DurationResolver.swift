//
//  DurationResolver.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import Foundation
import Observation

/// Resolves unknown track durations via `InnerTube` + `DurationCache`,
/// shared by every song row and grid cell. Consolidates the copy-pasted
/// `@State resolvedDuration` + `resolveDuration()` + `.durationDidUpdate`
/// receiver previously in each row.
@Observable
final class DurationResolver {
    var resolved = 0

    func effectiveDuration(known: Int) -> Int {
        known > 0 ? known : resolved
    }

    func resolve(videoId: String, knownDuration: Int) async {
        guard knownDuration <= 0 else { return }
        if let cached = DurationCache.get(videoId), cached > 0 {
            resolved = cached
            return
        }
        guard !DurationCache.isPending(videoId) else { return }
        DurationCache.markPending(videoId)
        do {
            resolved = try await InnerTube.shared.fetchDuration(videoId: videoId)
        } catch {
            DurationCache.clearPending(videoId)
        }
    }

    func handleUpdate(_ notification: Notification, videoId: String?) {
        guard let vid = notification.userInfo?["videoId"] as? String, vid == videoId else { return }
        resolved = DurationCache.get(vid) ?? 0
    }
}
