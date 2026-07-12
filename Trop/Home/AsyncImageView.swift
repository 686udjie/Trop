//
//  AsyncImageView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Nuke
import SwiftUI

struct AsyncImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholderView
                }
            }
            .task(id: url) {
                await loadImage(targetSize: geometry.size)
            }
        }
    }

    private func loadImage(targetSize: CGSize) async {
        guard let urlString = url, let url = URL(string: urlString) else {
            loadedImage = nil
            return
        }
        let scale = displayScale
        let displaySize = CGSize(
            width: targetSize.width * scale,
            height: targetSize.height * scale
        )
        let request: ImageRequest
        if contentMode == .fill {
            request = ImageRequest(
                url: url,
                processors: [.resize(size: displaySize, unit: .pixels, contentMode: .aspectFill)]
            )
        } else {
            request = ImageRequest(url: url)
        }
        do {
            let image = try await ImagePipeline.shared.image(for: request)
            guard !Task.isCancelled else { return }
            loadedImage = image
        } catch {
            guard !Task.isCancelled else { return }
            loadedImage = nil
        }
    }

    private var placeholderView: some View {
        Image(systemName: "music.note")
            .resizable()
            .scaledToFit()
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
    }
}
