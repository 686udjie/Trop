//
//  ImagePreloader.swift
//  Trop
//
//  Created by 686udjie on 14/07/2026.
//

import Foundation
import Nuke

actor ImagePreloader {
    private let prefetcher = ImagePrefetcher(
        pipeline: ImagePipeline.shared,
        maxConcurrentRequestCount: 8
    )
    private var pending: [URL] = []
    private var pendingSet: Set<URL> = []
    private var isActive = false
    private let batchSize: Int
    private var seen: Set<URL> = []
    private var seenOrder: [URL] = []
    private static let maxSeen = 1000
    private var lastPreloadAt: Date = .distantPast
    private static let minPreloadInterval: TimeInterval = 0.4
    private static let maxPreloadBatch = 60

    nonisolated static let shared = ImagePreloader()

    init(batchSize: Int = 20) {
        self.batchSize = batchSize
    }

    func preload(_ urls: [URL]) {
        let now = Date()
        _ = now.timeIntervalSince(lastPreloadAt) < Self.minPreloadInterval
        lastPreloadAt = now

        var fresh: [URL] = []
        fresh.reserveCapacity(min(urls.count, Self.maxPreloadBatch))
        for url in urls {
            guard fresh.count < Self.maxPreloadBatch else { break }
            guard !seen.contains(url), !pendingSet.contains(url) else { continue }
            fresh.append(url)
            pendingSet.insert(url)
            markSeen(url)
        }
        guard !fresh.isEmpty else { return }
        pending.append(contentsOf: fresh)
        // Cap queue depth so a huge library doesn't pin memory.
        if pending.count > 200 {
            let drop = pending.count - 200
            for url in pending.prefix(drop) { pendingSet.remove(url) }
            pending = Array(pending.dropFirst(drop))
        }
        prefetchNextBatch()
    }

    func append(_ urls: [URL]) {
        preload(urls)
    }

    private func markSeen(_ url: URL) {
        seen.insert(url)
        seenOrder.append(url)
        if seenOrder.count > Self.maxSeen {
            let drop = seenOrder.count - Self.maxSeen
            for url in seenOrder.prefix(drop) { seen.remove(url) }
            seenOrder = Array(seenOrder.dropFirst(drop))
        }
    }

    private func prefetchNextBatch() {
        guard !pending.isEmpty else {
            isActive = false
            return
        }

        let batch = Array(pending.prefix(batchSize))
        pending = Array(pending.dropFirst(batchSize))
        for url in batch { pendingSet.remove(url) }
        isActive = true

        prefetcher.startPrefetching(with: batch)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await self?.prefetchNextBatch()
        }
    }

    func cancel() {
        prefetcher.stopPrefetching()
        pending = []
        pendingSet = []
        isActive = false
    }

    func resetSeen() {
        seen = []
        seenOrder = []
    }
}
