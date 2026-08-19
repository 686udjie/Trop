//
//  VideoPlayerView.swift
//  Trop
//
//  Created by 686udjie on 19/07/2026.
//

import SwiftUI
import Libmpv

/// Hosts mpv's video output via the PlayerController-owned CAMetalLayer
struct VideoPlayerView: View {
    var body: some View {
        MpvVideoView()
            .background(Color.black)
    }
}

struct MpvVideoView: UIViewRepresentable {
    func makeUIView(context: UIViewRepresentableContext<MpvVideoView>) -> MpvVideoUIView {
        MpvVideoUIView()
    }

    func updateUIView(_ uiView: MpvVideoUIView, context: UIViewRepresentableContext<MpvVideoView>) {
        uiView.syncLayer()
    }
}

final class MpvVideoUIView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.addSublayer(PlayerController.shared.videoLayer)
        syncLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        layer.addSublayer(PlayerController.shared.videoLayer)
        syncLayer()
    }

    func syncLayer() {
        let mpvLayer = PlayerController.shared.videoLayer
        guard mpvLayer.superlayer === layer else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.windowScene?.screen.nativeScale ?? traitCollection.displayScale
        let drawableWidth = max(1, Int((bounds.width * scale).rounded(.down)) - 1)
        let drawableHeight = max(1, Int((bounds.height * scale).rounded(.down)) - 1)
        let logicalSize = CGSize(
            width: CGFloat(drawableWidth) / scale,
            height: CGFloat(drawableHeight) / scale
        )
        mpvLayer.bounds = CGRect(origin: .zero, size: logicalSize)
        mpvLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        mpvLayer.contentsScale = scale
        mpvLayer.drawableSize = CGSize(width: drawableWidth, height: drawableHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncLayer()
    }
}
