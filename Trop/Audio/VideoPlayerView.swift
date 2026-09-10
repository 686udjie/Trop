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
        var scale: CGFloat = 3
        if let native = window?.windowScene?.screen.nativeScale, native > 0 {
            scale = native
        } else {
            let trait = traitCollection.displayScale
            let current = UITraitCollection.current.displayScale
            if trait > 0 {
                scale = trait
            } else if current > 0 {
                scale = current
            }
        }
        let drawableWidth = max(1, Int((bounds.width * scale).rounded()))
        let drawableHeight = max(1, Int((bounds.height * scale).rounded()))
        mpvLayer.frame = bounds
        mpvLayer.contentsScale = scale
        let newDrawable = CGSize(width: drawableWidth, height: drawableHeight)
        if mpvLayer.drawableSize != newDrawable {
            mpvLayer.drawableSize = newDrawable
        }
        PlayerController.shared.refreshVideoGeometryIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncLayer()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncLayer()
    }
}
