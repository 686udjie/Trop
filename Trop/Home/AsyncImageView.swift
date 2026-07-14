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
        guard let urlString = url else {
            loadedImage = nil
            return
        }
        let normalized = normalizeThumbnailURL(urlString)
        guard let url = URL(string: normalized) else {
            loadedImage = nil
            return
        }
        let scale = displayScale
        // Prevent zero-size layout passes from causing degenerate image cache requests.
        let minPixels: CGFloat = 120 * scale
        let displaySize = CGSize(
            width: max(targetSize.width * scale, minPixels),
            height: max(targetSize.height * scale, minPixels)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                loadedImage = image
            }
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

private func normalizeThumbnailURL(_ urlString: String) -> String {
    var url = urlString

    url = url.replacingOccurrences(of: "(?<=[sh]\\d+)-c", with: "", options: .regularExpression)

    if url.contains("googleusercontent.com") || url.contains("ggpht.com") {
        if let match = try? NSRegularExpression(pattern: "w(\\d+)-h(\\d+)"),
           let result = match.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) {
            guard let wRange = Range(result.range(at: 1), in: url),
                  let hRange = Range(result.range(at: 2), in: url) else { return url }
            let w = Int(url[wRange]) ?? 0
            let h = Int(url[hRange]) ?? 0
            let newW = max(w, 600)
            let newH = max(h, 600)
            if newW != w || newH != h {
                url = url.replacingOccurrences(
                    of: "w\(w)-h\(h)",
                    with: "w\(newW)-h\(newH)"
                )
            }
        }
    }

    return url
}
