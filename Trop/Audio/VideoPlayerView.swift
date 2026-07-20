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
    let player = PlayerController.shared

    var body: some View {
        MpvVideoView()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onDisappear {
                player.setVideoMode(false)
            }
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
        let mpvLayer = PlayerController.shared.videoLayer
        mpvLayer.frame = bounds
        mpvLayer.contentsScale = window?.windowScene?.screen.nativeScale ?? 1.0
        layer.addSublayer(mpvLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        layer.addSublayer(PlayerController.shared.videoLayer)
    }

    func syncLayer() {
        let mpvLayer = PlayerController.shared.videoLayer
        mpvLayer.frame = bounds
        mpvLayer.contentsScale = window?.windowScene?.screen.nativeScale ?? 1.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncLayer()
    }
}
