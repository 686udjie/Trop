//
//  QueueView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct QueueView<ProgressSlider: View>: View {
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

    @ObservedObject private var likeStore = LikeStore.shared
    @State private var showSongMenu = false

    private var isLiked: Bool {
        guard let song = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil else { return false }
        return likeStore.isLiked(videoId: song.videoId)
    }

    var body: some View {
        queueContent
    }

    // MARK: - Queue Content

    private var queueContent: some View {
        VStack(spacing: 0) {
            queueHeader
                .padding(.horizontal, 20)

            playbackPillsRow

            queueListHeaderRow

            ScrollViewReader { proxy in
                List {
                    if np.queueSongs.isEmpty {
                        emptyQueueRow
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(Array(np.queueSongs.enumerated()), id: \.element.videoId) { index, song in
                            queueRow(song: song, index: index)
                        }
                        .onMove(perform: np.moveQueueSongs)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.colorScheme, .dark)
                .scrollIndicators(.hidden)
                .layoutPriority(1)
                .onAppear {
                    if np.queueSongs.indices.contains(np.queueIndex) {
                        proxy.scrollTo(np.queueSongs[np.queueIndex].videoId, anchor: .center)
                    }
                }
            }

            // Bottom control section is now naturally pinned to the bottom
            VStack(spacing: 16) {
                progressSlider()
                    .padding(.top, 16) // Match the artist→slider gap (16) used in the big player

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
            .padding(.bottom, 16)
        }
    }

    // MARK: - Queue Header

    private var queueHeader: some View {
        HStack(spacing: 12) {
            if let uiImage = np.thumbnailUIImage {
                let cropped = uiImage.centerCroppedSquare()
                Image(uiImage: cropped)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 64, height: 64)
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

            Button {
                guard let song = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil else { return }
                Task { await likeStore.toggle(song: song) }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundStyle(isLiked ? .white : .white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }

            let currentSong = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil
            if let song = currentSong {
                Button {
                    showSongMenu = true
                } label: {
                    Text("\u{22EE}")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                }
                .sheet(isPresented: $showSongMenu) {
                    SongMenuSheet(
                        song: song,
                        onNavigate: { pendingRoute.wrappedValue = $0 }
                    )
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                showQueue = false
            }
        }
    }

    // MARK: - Queue Sub-Views

    private var playbackPillsRow: some View {
        HStack(spacing: 8) {
            pillButton(isOn: $isShuffleOn, icon: "shuffle") {
                if isShuffleOn {
                    np.shuffleQueue()
                } else {
                    np.disableShuffle()
                }
            }
            pillButton(isOn: $isRepeatOn, icon: "repeat")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func pillButton(isOn: Binding<Bool>, icon: String, action: (() -> Void)? = nil) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(isOn.wrappedValue ? .white.opacity(0.15) : .white.opacity(0.07))
                )
        }
    }

    private var queueListHeaderRow: some View {
        HStack {
            Text("Queue")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var emptyQueueRow: some View {
        HStack {
            Spacer()
            Text("Queue is empty")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Actions

    private func queueRow(song: SongItem, index: Int) -> some View {
        let isCurrent = index == np.queueIndex

        return Button {
            playSong(at: index)
        } label: {
            QueueSongRow(
                song: song,
                isCurrent: isCurrent,
                isPlayed: index < np.queueIndex
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(
            Group {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .padding(.horizontal, 12)
                }
            }
        )
        .listRowSeparator(.hidden)
        .onDrag {
            NSItemProvider(object: song.videoId as NSString)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3)) {
                    removeSong(at: index)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func playSong(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        np.lastManualSkipTime = Date()
        np.queueIndex = index
        let song = np.queueSongs[index]
        np.update(title: song.title, artist: song.artists.map(\.name).joined(separator: ", "), videoId: song.videoId, artists: song.artists)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                Log.nowPlaying.error("resolveAndPlay failed: \(error)")
                if np.videoId == song.videoId {
                    np.isPlaying = false
                }
            }
        }
    }

    private func removeSong(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        let wasCurrent = index == np.queueIndex
        let removedVideoId = np.queueSongs[index].videoId
        np.queueSongs.remove(at: index)
        if wasCurrent {
            if np.queueSongs.isEmpty {
                np.queueIndex = 0
                np.isPlaying = false
                np.persistQueueState()
                Task { @MainActor in PlayerController.shared.setPaused(true) }
                return
            }
            let nextIndex = min(index, np.queueSongs.count - 1)
            np.queueIndex = nextIndex
            let song = np.queueSongs[nextIndex]
            np.update(title: song.title, artist: song.artists.map(\.name).joined(separator: ", "), videoId: song.videoId, artists: song.artists)
            Task {
                do {
                    try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
                } catch {
                    Log.nowPlaying.error("removeSong auto-play failed: \(error)")
                }
            }
        } else {
            np.repairQueueIndex()
        }
        np.persistQueueState()
        if !wasCurrent && removedVideoId == np.videoId {
            np.repairQueueIndex()
        }
    }
}

// MARK: - Queue Song Row

struct QueueSongRow: View {
    let song: SongItem
    var isCurrent = false
    var isPlayed = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isPlayed ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: song.title,
                    font: .subheadline.weight(isCurrent ? .semibold : .medium),
                    frameHeight: 20,
                    textColor: titleColor
                )

                let artistStr = song.artists.map(\.name).joined(separator: ", ")
                if !artistStr.isEmpty {
                    Text(artistStr)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(isPlayed ? 0.35 : 0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    private var titleColor: Color {
        isPlayed && !isCurrent ? Color.white.opacity(0.45) : .white
    }
}
