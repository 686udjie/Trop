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
    private var isActive = false
    private var batchTask: Task<Void, Never>?
    private let batchSize: Int

    nonisolated static let shared = ImagePreloader()

    init(batchSize: Int = 20) {
        self.batchSize = batchSize
    }

    func preload(_ urls: [URL]) {
        pending = deduped(urls)
        startPrefetchChainIfNeeded()
    }

    func append(_ urls: [URL]) {
        pending.append(contentsOf: deduped(urls))
        startPrefetchChainIfNeeded()
    }

    private func startPrefetchChainIfNeeded() {
        guard !isActive else { return }
        prefetchNextBatch()
    }

    private func deduped(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func prefetchNextBatch() {
        guard !pending.isEmpty else {
            isActive = false
            batchTask = nil
            return
        }

        let batch = Array(pending.prefix(batchSize))
        pending = Array(pending.dropFirst(batchSize))
        isActive = true

        prefetcher.startPrefetching(with: batch)

        batchTask?.cancel()
        batchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self?.prefetchNextBatch()
        }
    }

    func cancel() {
        batchTask?.cancel()
        batchTask = nil
        prefetcher.stopPrefetching()
        pending = []
        isActive = false
    }
}
