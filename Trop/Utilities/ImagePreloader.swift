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
        maxConcurrentRequestCount: 4
    )
    private var pending: [URL] = []
    private var isActive = false
    private let batchSize: Int

    nonisolated static let shared = ImagePreloader()

    init(batchSize: Int = 10) {
        self.batchSize = batchSize
    }

    func preload(_ urls: [URL]) {
        pending = urls
        prefetchNextBatch()
    }

    func append(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        if !isActive {
            prefetchNextBatch()
        }
    }

    private func prefetchNextBatch() {
        guard !pending.isEmpty else {
            isActive = false
            return
        }

        let batch = Array(pending.prefix(batchSize))
        pending = Array(pending.dropFirst(batchSize))
        isActive = true

        prefetcher.startPrefetching(with: batch)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.prefetchNextBatch()
        }
    }

    func cancel() {
        prefetcher.stopPrefetching()
        pending = []
        isActive = false
    }
}
