//
//  CachedAvatarView.swift
//  Trop
//
//  Nuke-backed profile avatar: memory + disk cached via the shared pipeline,
//  so Discord/Last.fm pictures don't refetch every time settings opens.
//  (SwiftUI's AsyncImage uses URLCache, not Nuke's disk cache.)
//

import SwiftUI
import UIKit

struct CachedAvatarView: View {
    let url: URL?
    var size: CGFloat = 56

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed || url == nil {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    ProgressView()
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) { await load() }
    }

    private func load() async {
        failed = false
        guard let url else {
            image = nil
            return
        }
        // Keep the previous image until the new one arrives — no flicker
        // when the URL is unchanged and already cached.
        if let cached = ArtworkLoader.cachedImage(for: url) {
            image = cached
            return
        }
        do {
            let fetched = try await ArtworkLoader.image(for: url)
            guard !Task.isCancelled else { return }
            image = fetched
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}
