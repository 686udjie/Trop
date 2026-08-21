//
//  FullPlayerView.swift
//  Trop
//
//  Created by 686udjie on 18/07/2026.
//

import SwiftUI

struct FullPlayerView: View {
    let onCollapse: () -> Void

    @Environment(SettingsStore.self) private var settings
    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared

    @State private var editingProgress: Float = 0
    @State private var isEditingSlider = false
    @State private var collapseOffset: CGFloat = 0

    @State private var isLiked = false
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var pendingRoute: DetailRoute?
    @State private var showSongMenu = false
    @State private var artworkEntryOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if settings.playerBackgroundStyle == .solid {
                Color.black
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        np.dominantColors.first ?? Color(red: 0.15, green: 0.15, blue: 0.2),
                        np.dominantColors.last ?? Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: np.dominantColors)

                Circle()
                    .fill(np.dominantColors.first ?? .blue)
                    .frame(width: 400, height: 400)
                    .blur(radius: 120)
                    .opacity(0.45)
                    .offset(y: -150)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .contentShape(Rectangle().size(width: 60, height: 30))
                    .accessibilityLabel("Collapse player")

                    if showLyrics {
                    LyricsView(
                        showLyrics: $showLyrics,
                        showQueue: $showQueue,
                        isRepeatOn: $np.isRepeatOn,
                        pendingRoute: $pendingRoute,
                        progressSlider: { progressSlider }
                    )
                    } else if showQueue {
                    QueueView(
                        showLyrics: $showLyrics,
                        showQueue: $showQueue,
                        isLiked: $isLiked,
                        isShuffleOn: $np.isShuffleOn,
                        isRepeatOn: $np.isRepeatOn,
                        editingProgress: $editingProgress,
                        isEditingSlider: $isEditingSlider,
                        pendingRoute: $pendingRoute,
                        progressSlider: { progressSlider }
                    )
                    } else {
                    Spacer(minLength: 8)

                    artwork
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: np.isVideoMode ? 10 : 24,
                                style: .continuous
                            )
                        )
                        .shadow(
                            color: .black.opacity(0.4),
                            radius: 20,
                            x: 0,
                            y: 12
                        )
                        .padding(.horizontal, 32)

                        Spacer(minLength: np.isVideoMode ? 12 : 16)

                    titleAndActionsRow
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)

                    progressSlider
                        .padding(.bottom, 16)

                    PlaybackControlsRow(
                        isPlaying: np.isPlaying,
                        hasPrevious: np.hasPrevious,
                        hasNext: np.hasNext,
                        onPrevious: { np.playPrevious() },
                        onPlayPause: { player.togglePlayPause() },
                        onNext: { np.playNext() }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: np.isPlaying)
                    .padding(.bottom, 8)

                    SecondaryActionsRow(
                        showLyrics: $showLyrics,
                        showQueue: $showQueue,
                        isRepeatOn: $np.isRepeatOn,
                        onRepeat: {}
                    )

                    Spacer(minLength: 8)
                    }
            }
        }
        .offset(y: collapseOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: collapseOffset)
        .simultaneousGesture(collapseDrag)
        .onChange(of: np.videoId) { _, _ in
            np.isVideoMode = false
            preloadLyrics()
        }
        .onChange(of: np.queueSongs.count) { _, _ in
            np.preloadNeighborArtwork()
            preloadLyrics()
        }
        .onChange(of: np.queueIndex) { _, _ in
            np.preloadNeighborArtwork()
        }
        .onChange(of: showQueue) { _, newValue in
            if newValue { np.preloadNeighborArtwork() }
        }
        .task { np.preloadNeighborArtwork() }
        .sheet(isPresented: $showSongMenu) {
            if let song = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil {
                PlayerMenuSheet(song: song, onCollapseRequest: { onCollapse() })
            }
        }
        .background(
            Color.clear
                .detailRouteSheet(item: $pendingRoute)
        )
    }

    // MARK: - Gestures

    /// Swipe left/right on the artwork to skip tracks (toggleable in Settings).
    /// Blocked at the queue's ends (no movement); on skip, the incoming
    /// artwork slides in from the swipe direction.
    private var artworkSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard settings.artworkSwipeNavigation else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -60, np.hasNext {
                    np.playNext()
                    slideInArtwork(fromLeft: false)
                } else if value.translation.width > 60, np.hasPrevious {
                    np.playPrevious()
                    slideInArtwork(fromLeft: true)
                }
            }
    }

    private func slideInArtwork(fromLeft: Bool) {
        artworkEntryOffset = fromLeft ? -600 : 600
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            artworkEntryOffset = 0
        }
    }

    /// Swipe down anywhere to collapse. Vertical-dominant drags only, and
    /// disabled while lyrics/queue are shown so their ScrollViews keep
    /// owning vertical pans.
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !showLyrics, !showQueue else { return }
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width) else { return }
                collapseOffset = value.translation.height
            }
            .onEnded { value in
                defer { collapseOffset = 0 }
                guard !showLyrics, !showQueue else { return }
                let isVertical = value.translation.height > abs(value.translation.width)
                if isVertical, value.translation.height > 140 {
                    onCollapse()
                }
            }
    }

    // MARK: - Player Content

    private func preloadLyrics() {
        guard let id = np.videoId else { return }
        let upcoming = Array(np.queueSongs.suffix(from: np.queueIndex + 1).prefix(3).map(\.videoId))
        Task { await LyricsService.shared.preload(videoId: id, upcoming: upcoming) }
    }

    private var titleAndActionsRow: some View {
        HStack(alignment: .center) {
            let title = np.title
            let artist = np.displayArtist
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(
                    text: title,
                    font: .title3.weight(.bold),
                    frameHeight: 28
                )

                if !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    isLiked.toggle()
                    if isLiked, SettingsStore.shared.autoDownloadOnLike,
                       let song = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil {
                        Task { await DownloadManager.shared.download(song: song) }
                    }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isLiked ? .red : .white)
                        .frame(width: 36, height: 36)
                }

            let currentSong = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil
            if currentSong != nil {
                Button {
                    showSongMenu = true
                } label: {
                    Text("\u{22EE}")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Song options")
            }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if np.isVideoMode, np.hasVideo {
                VideoPlayerView()
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .onTapGesture {
                        np.isVideoMode = false
                    }
            } else {
                ZStack {
                    if let uiImage = np.thumbnailUIImage {
                        let cropped = uiImage.centerCroppedSquare()
                        GeometryReader { geo in
                            Image(uiImage: cropped)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    } else {
                        ZStack {
                            Color.white.opacity(0.1)
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .aspectRatio(1.0, contentMode: .fit)
                .onTapGesture {
                    guard np.hasVideo else { return }
                    player.setVideoMode()
                }
            }
        }
        .offset(x: artworkEntryOffset)
        .gesture(artworkSwipe)
    }

    private var progressSlider: some View {
        VStack(spacing: 6) {
            ProgressBar(
                progress: Binding(
                    get: { isEditingSlider ? editingProgress : np.progress },
                    set: { editingProgress = $0 }
                ),
                accentColor: np.dominantColors.first ?? .white,
                isPlaying: np.isPlaying,
                onEditingChanged: { editing in
                    if editing {
                        editingProgress = np.progress
                    } else {
                        let target = TimeInterval(editingProgress) * np.duration
                        player.seek(to: target)
                        np.currentTime = target
                        player.updateNowPlayingProgress()
                    }
                    isEditingSlider = editing
                }
            )

            HStack {
                Text(timeString(isEditingSlider
                    ? TimeInterval(editingProgress) * np.duration
                    : np.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Text(timeString(np.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 32)
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        return "\(Int(t) / 60):\(String(format: "%02d", Int(t) % 60))"
    }
}
