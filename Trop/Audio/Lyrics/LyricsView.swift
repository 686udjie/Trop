//
//  LyricsView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI
import UIKit

struct LyricsView<ProgressSlider: View>: View {
    private let np = NowPlaying.shared
    private let player = PlayerController.shared

    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    @Binding var isShuffleOn: Bool
    @Binding var isRepeatOn: Bool
    @Binding var editingProgress: Float
    @Binding var isEditingSlider: Bool
    let pendingRoute: Binding<DetailRoute?>
    @ViewBuilder var progressSlider: () -> ProgressSlider

    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var activeIndex: Int = 0
    @State private var isFullscreen = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            lyricsBody
                .layoutPriority(1)

            if isFullscreen {
                fullscreenBottomRow
            } else {
                bottomBar
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.3), value: isFullscreen)
        .task(id: np.videoId) { await loadLyrics() }
        .onChange(of: np.currentTime) { _, _ in updateActiveLine() }
    }

    // MARK: - Header

    private var headerBar: some View {
        Color.clear
            .padding(.top, 16)
    }

    // MARK: - Lyrics Body

    private var lyricsBody: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("No lyrics available")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // Top spacer so first line isn't flush to the header
                            Spacer().frame(height: 24)

                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(index == activeIndex ? .white : .white.opacity(0.4))
                                    .animation(.easeInOut(duration: 0.25), value: activeIndex)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24)
                                    .id(line.id)
                                    .onTapGesture {
                                        if let t = line.startTime {
                                            player.seek(to: t)
                                            np.currentTime = t
                                        }
                                    }
                            }

                            // Bottom spacer so last line can scroll above the bottom bar
                            Spacer().frame(height: 24)
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: activeIndex) { _, newIndex in
                        guard lines.indices.contains(newIndex) else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo(lines[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared Song Info Row

    private func songInfoRow(showFullscreenButton: Bool) -> some View {
        HStack(spacing: 12) {
            if let uiImage = np.thumbnailUIImage {
                let cropped = uiImage.centerCroppedSquare()
                Image(uiImage: cropped)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 48, height: 48)
            }

            let title = np.title
            let artist = np.displayArtist
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: title,
                    font: .body.weight(.semibold),
                    frameHeight: 24
                )

                if !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            if showFullscreenButton {
                fullscreenToggleButton
            }

            threeDotsMenu
        }
    }

    private var fullscreenToggleButton: some View {
        Button {
            withAnimation { isFullscreen.toggle() }
        } label: {
            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
        }
    }

    private var threeDotsMenu: some View {
        Group {
            if let currentSong = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil {
                Menu {
                    Button {
                        UIPasteboard.general.string = currentSong.webUrl
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    if let artistId = currentSong.firstArtistBrowseId {
                        Button {
                            pendingRoute.wrappedValue = DetailRoute.artist(browseId: artistId)
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                        }
                    }
                    if let albumId = currentSong.firstAlbumBrowseId {
                        Button {
                            pendingRoute.wrappedValue = DetailRoute.album(browseId: albumId)
                        } label: {
                            Label("Go to Album", systemImage: "record.circle")
                        }
                    }
                } label: {
                    Text("\u{22EE}")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .menuOrder(.fixed)
            }
        }
    }

    // MARK: - Fullscreen Bottom Row

    private var fullscreenBottomRow: some View {
        VStack(spacing: 12) {
            songInfoRow(showFullscreenButton: true)

            progressSlider()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let uiImage = np.thumbnailUIImage {
                    let cropped = uiImage.centerCroppedSquare()
                    Image(uiImage: cropped)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 48, height: 48)
                }

                let title = np.title
                let artist = np.displayArtist
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: title,
                        font: .body.weight(.semibold),
                        frameHeight: 24
                    )

                    if !artist.isEmpty {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                fullscreenToggleButton

                threeDotsMenu
            }
            .padding(.horizontal, 20)

            progressSlider()

            PlaybackControlsRow(
                isPlaying: np.isPlaying,
                hasPrevious: np.hasPrevious,
                hasNext: np.hasNext,
                onPrevious: { np.playPrevious() },
                onPlayPause: { player.togglePlayPause() },
                onNext: { np.playNext() }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: np.isPlaying)

            SecondaryActionsRow(
                showLyrics: $showLyrics,
                showQueue: $showQueue,
                isRepeatOn: $isRepeatOn,
                onRepeat: {}
            )
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Data

    private func loadLyrics() async {
        guard let videoId = np.videoId else {
            lines = []
            return
        }
        isLoading = true
        lines = []
        activeIndex = 0
        do {
            let result = try await LyricsService.shared.fetchLyrics(videoId: videoId)
            await MainActor.run {
                self.lines = result
                self.isLoading = false
                self.updateActiveLine()
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func updateActiveLine() {
        guard !lines.isEmpty else { return }
        let t = np.currentTime
        var idx = 0
        for (i, line) in lines.enumerated() {
            guard let start = line.startTime else { continue }
            if start <= t {
                idx = i
            } else {
                break
            }
        }
        if idx != activeIndex {
            activeIndex = idx
        }
    }
}
