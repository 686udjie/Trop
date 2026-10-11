//
//  CanvasVideoView.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import AVFoundation
import SwiftUI
import UIKit

struct CanvasVideoView: View {
    let videoId: String?
    let title: String
    let artist: String
    let album: String?
    let isPlaying: Bool
    let enabled: Bool
    let onDominantColorsChange: ([Color]?) -> Void

    @State private var clipURL: URL?
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.clear
                .task(id: "\(videoId ?? "")-\(enabled)") {
                    onDominantColorsChange(nil)
                    await resolve()
                }
            if let clipURL {
                CanvasLooperView(url: clipURL, isPlaying: isPlaying, onFirstFrame: {
                    withAnimation(.easeInOut(duration: 0.6)) { revealed = true }
                })
                .opacity(revealed ? 1 : 0)
                .task(id: clipURL) {
                    let colors = await dominantColors(from: clipURL)
                    guard !Task.isCancelled else { return }
                    onDominantColorsChange(colors)
                }
            }
        }
    }

    private func resolve() async {
        revealed = false
        clipURL = nil
        guard enabled, let videoId else { return }
        if let cached = await CanvasRepository.shared.cachedClip(videoId: videoId) {
            guard !Task.isCancelled else { return }
            clipURL = cached.url
        }
        guard let clip = await CanvasRepository.shared.canvasFor(
            videoId: videoId, title: title, artist: artist, album: album
        ) else {
            return
        }
        guard !Task.isCancelled else { return }
        clipURL = clip.url
    }

    private func dominantColors(from url: URL) async -> [Color]? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        do {
            let (image, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            return UIImage(cgImage: image).extractDominantColors()
        } catch {
            return nil
        }
    }
}

@MainActor
final class CanvasPlayerPreloader {
    static let shared = CanvasPlayerPreloader()

    private var preparedURL: URL?
    private var preparedPlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var prerollURL: URL?
    private var readinessObservation: NSKeyValueObservation?

    func preload(url: URL) {
        guard prerollURL != url else { return }
        let player = player(for: url)
        prerollURL = url
        readinessObservation = player.observe(\.status, options: [.initial, .new]) { [weak self, weak player] _, _ in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player,
                      preparedURL == url, preparedPlayer === player,
                      prerollURL == url, player.status == .readyToPlay
                else { return }
                readinessObservation?.invalidate()
                readinessObservation = nil
                player.preroll(atRate: 1) { _ in }
            }
        }
    }

    func player(for url: URL) -> AVQueuePlayer {
        if preparedURL == url, let preparedPlayer { return preparedPlayer }

        readinessObservation?.invalidate()
        readinessObservation = nil
        preparedPlayer?.pause()
        looper = nil
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        preparedURL = url
        preparedPlayer = player
        prerollURL = nil
        return player
    }
}

private struct CanvasLooperView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let onFirstFrame: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFirstFrame: onFirstFrame)
    }

    func makeUIView(context: Context) -> CanvasPlayerUIView {
        let view = CanvasPlayerUIView()
        context.coordinator.attach(to: view, url: url, isPlaying: isPlaying)
        return view
    }

    func updateUIView(_ uiView: CanvasPlayerUIView, context: Context) {
        context.coordinator.update(url: url, isPlaying: isPlaying)
    }

    static func dismantleUIView(_ uiView: CanvasPlayerUIView, coordinator: Coordinator) {
        coordinator.detach()
    }
}

private final class CanvasPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer {
        // layerClass above guarantees the backing layer type.
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }
}

/// Owns the queue player + looper for one clip URL. Torn down with the view.
@MainActor
private final class Coordinator {
    private weak var view: CanvasPlayerUIView?
    private var player: AVQueuePlayer?
    private var readyObservation: NSKeyValueObservation?
    private var currentURL: URL?
    private var isPlaying = false
    private var didReportFirstFrame = false
    private let onFirstFrame: () -> Void
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    init(onFirstFrame: @escaping () -> Void) {
        self.onFirstFrame = onFirstFrame
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.player?.pause() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isPlaying else { return }
                player?.play()
            }
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    func attach(to view: CanvasPlayerUIView, url: URL, isPlaying: Bool) {
        self.view = view
        update(url: url, isPlaying: isPlaying)
    }

    func update(url: URL, isPlaying: Bool) {
        self.isPlaying = isPlaying
        if currentURL != url { rebuild(url: url) }
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }

    func detach() {
        readyObservation?.invalidate()
        readyObservation = nil
        player?.pause()
        view?.playerLayer.player = nil
        player = nil
        currentURL = nil
    }

    private func rebuild(url: URL) {
        detach()
        didReportFirstFrame = false
        let player = CanvasPlayerPreloader.shared.player(for: url)
        self.player = player
        self.currentURL = url
        view?.playerLayer.player = player
        view?.playerLayer.videoGravity = .resizeAspectFill
        readyObservation = view?.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                guard let self, !didReportFirstFrame else { return }
                didReportFirstFrame = true
                onFirstFrame()
            }
        }
        if isPlaying { player.play() }
    }
}
