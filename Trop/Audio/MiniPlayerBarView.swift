//
//  MiniPlayerBarView.swift
//  Trop
//
//  Created by 686udjie on 18/07/2026.
//

import SwiftUI
import Nuke

/// The mini player bar, hosted as the TabView's native bottom accessory.
/// Swiping left/right pages through the queue with the artwork and text sliding
/// together, exactly tracking the drag state. When the tab bar minimizes on
/// scroll the bar collapses into a compact inline form that merges with the
/// tab bar, matching the Apple Music behavior; otherwise it renders as the
/// 48pt floating glass capsule with a bottom progress line.
struct MiniPlayerBarView: View {
    let onExpand: () -> Void

    @Environment(MiniPlayerScrollState.self) private var scrollState
    @Environment(\.colorScheme) private var colorScheme

    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared

    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: DragAxis?
    @State private var isCommitting = false

    private enum DragAxis {
        case horizontal
        case vertical
    }

    private var isInline: Bool {
        scrollState.isInline
    }

    private var barHeight: CGFloat {
        isInline ? 44 : 48
    }

    private var artworkSize: CGFloat {
        isInline ? 26 : 30
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var artistColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.65)
    }

    var body: some View {
        HStack(spacing: 0) {
            pagingArea
            playPauseButton
                .padding(.trailing, isInline ? 14 : 20)
        }
        .frame(height: barHeight)
        .overlay(alignment: .bottom) { progressLine }
        .padding(.horizontal, isInline ? 40 : 0)
        .onChange(of: np.videoId) { _, _ in
            dragOffset = 0
            preloadLyrics()
        }
        .onChange(of: np.queueSongs.count) { _, _ in
            dragOffset = 0
            np.preloadNeighborArtwork()
        }
        .onChange(of: np.queueIndex) { _, _ in
            dragOffset = 0
            np.preloadNeighborArtwork()
        }
        .task { np.preloadNeighborArtwork() }
    }

    private func preloadLyrics() {
        guard let id = np.videoId else { return }
        let upcoming = Array(np.queueSongs.suffix(from: np.queueIndex + 1).prefix(3).map(\.videoId))
        Task { await LyricsService.shared.preload(videoId: id, upcoming: upcoming) }
    }

    // MARK: - Paging area

    private var pagingArea: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            ZStack(alignment: .center) {
                if let prev = prevSong {
                    page(for: prev, width: pageWidth)
                        .offset(x: -pageWidth)
                }
                if let current = currentSong {
                    page(for: current, width: pageWidth)
                }
                if let next = nextSong {
                    page(for: next, width: pageWidth)
                        .offset(x: pageWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(x: dragOffset)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(pageWidth: pageWidth))
            .onTapGesture { onExpand() }
        }
        .frame(height: barHeight)
    }

    private func page(for song: SongItem, width: CGFloat) -> some View {
        HStack(spacing: isInline ? 6 : 8) {
            barArtwork(for: song.videoId)

            VStack(alignment: .leading, spacing: 0) {
                if isInline {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(titleColor)
                } else {
                    MarqueeText(
                        text: song.title,
                        font: .system(size: 13, weight: .semibold),
                        frameHeight: 16,
                        textColor: titleColor
                    )
                }

                Text(artistDisplayString(from: song.artists))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(artistColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(.leading, isInline ? 14 : 16)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func barArtwork(for videoId: String) -> some View {
        let isCurrent = videoId == np.videoId
        ZStack {
            if isCurrent, let uiImage = np.thumbnailUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                MiniArtworkView(videoId: videoId)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: isInline ? 5 : 6, style: .continuous))
    }

    private var playPauseButton: some View {
        Button(action: { player.togglePlayPause() }) {
            Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: isInline ? 16 : 17))
        }
        .accessibilityLabel(np.isPlaying ? "Pause" : "Play")
    }

    private var progressLine: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.tint)
                .frame(width: geo.size.width * CGFloat(np.progress))
        }
        .frame(height: 1.5)
        .padding(.horizontal, 14)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
    }

    // MARK: - Data

    private var currentSong: SongItem? {
        guard np.queueSongs.indices.contains(np.queueIndex) else { return nil }
        return np.queueSongs[np.queueIndex]
    }

    private var prevSong: SongItem? {
        guard np.queueSongs.indices.contains(np.queueIndex - 1) else { return nil }
        return np.queueSongs[np.queueIndex - 1]
    }

    private var nextSong: SongItem? {
        guard np.queueSongs.indices.contains(np.queueIndex + 1) else { return nil }
        return np.queueSongs[np.queueIndex + 1]
    }

    // MARK: - Gesture

    private func dragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !isCommitting else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal
                        : .vertical
                }
                guard dragAxis == .horizontal else { return }

                let minOffset = nextSong != nil ? -pageWidth : 0
                let maxOffset = prevSong != nil ? pageWidth : 0
                dragOffset = min(max(value.translation.width, minOffset), maxOffset)
            }
            .onEnded { value in
                guard !isCommitting else { return }
                defer { dragAxis = nil }

                switch dragAxis {
                case .horizontal:
                    if dragOffset <= -pageWidth * 0.35, nextSong != nil {
                        commitSwipe(to: .next, pageWidth: pageWidth)
                    } else if dragOffset >= pageWidth * 0.35, prevSong != nil {
                        commitSwipe(to: .previous, pageWidth: pageWidth)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                case .vertical:
                    if value.translation.height < -40 {
                        onExpand()
                    }
                case nil:
                    break
                }
            }
    }

    private enum SwipeDirection {
        case next
        case previous
    }

    private func commitSwipe(to direction: SwipeDirection, pageWidth: CGFloat) {
        isCommitting = true
        let target: CGFloat = direction == .next ? -pageWidth : pageWidth
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = target
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            switch direction {
            case .next: np.playNext()
            case .previous: np.playPrevious()
            }
            withAnimation(nil) { dragOffset = 0 }
            isCommitting = false
        }
    }
}

// MARK: - Per-song artwork (memory-cache fast path)

@MainActor
private struct MiniArtworkView: View {
    let videoId: String

    @State private var uiImage: UIImage?

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.12)
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .onAppear { load() }
    }

    private func load() {
        if let cached = cachedArtwork(for: videoId) {
            uiImage = cached
            return
        }
        guard let url = URL(string: NowPlaying.artworkURL(for: videoId)) else { return }
        Task {
            do {
                let image = try await ImagePipeline.shared.image(for: url)
                let cropped = image.centerCroppedSquare()
                await MainActor.run { uiImage = cropped }
            } catch {
                Log.nowPlaying.debug("Mini artwork load failed: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
private func cachedArtwork(for videoId: String) -> UIImage? {
    guard let url = URL(string: NowPlaying.artworkURL(for: videoId)),
          let image = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: url), caches: .all)?.image
    else { return nil }
    return image.centerCroppedSquare()
}
