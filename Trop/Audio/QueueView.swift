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
    @Binding var isLiked: Bool
    @Binding var isShuffleOn: Bool
    @Binding var isRepeatOn: Bool
    @Binding var isAutoplayOn: Bool
    @Binding var editingProgress: Float
    @Binding var isEditingSlider: Bool
    let pendingRoute: Binding<DetailRoute?>
    @ViewBuilder var progressSlider: () -> ProgressSlider

    private var upcomingSongs: [SongItem] {
        Array(np.queueSongs.suffix(from: np.queueIndex + 1))
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

            ScrollView {
                if !upcomingSongs.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(upcomingSongs.indices, id: \.self) { offset in
                            let absoluteIndex = np.queueIndex + 1 + offset
                            let song = upcomingSongs[offset]

                            QueueSongRow(song: song)
                                .onTapGesture {
                                    playSong(at: absoluteIndex)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(.spring(response: 0.3)) {
                                            removeSong(at: absoluteIndex)
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } else {
                    emptyQueueRow
                }
            }
            .scrollIndicators(.hidden)
            .layoutPriority(1)

            // Bottom control section is now naturally pinned to the bottom
            VStack(spacing: 16) {
                progressSlider()
                    .padding(.horizontal, 20)
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
                    .aspectRatio(contentMode: .fill)
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
            let artistLonger = !artist.isEmpty && artist.count > title.count
            let displayText = artistLonger ? title : (artist.isEmpty ? title : artist)
            let placeAtTop = !artistLonger
            VStack(alignment: .leading, spacing: 2) {
                if !placeAtTop {
                    Spacer(minLength: 0)
                }
                Text(displayText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if placeAtTop {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 64)

            Spacer()

            Button {
                isLiked.toggle()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundStyle(isLiked ? .white : .white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }

            let currentSong = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil
            if let song = currentSong {
                Menu {
                    Button {
                        UIPasteboard.general.string = song.webUrl
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    if let artistId = song.firstArtistBrowseId {
                        Button {
                            pendingRoute.wrappedValue = DetailRoute.artist(browseId: artistId)
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                        }
                    }
                    if let albumId = song.firstAlbumBrowseId {
                        Button {
                            pendingRoute.wrappedValue = DetailRoute.album(browseId: albumId)
                        } label: {
                            Label("Go to Album", systemImage: "record.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(90))
                }
                .menuOrder(.fixed)
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
            pillButton(isOn: $isShuffleOn, icon: "shuffle")
            pillButton(isOn: $isRepeatOn, icon: "repeat")
            pillButton(isOn: $isAutoplayOn, icon: "infinity")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func pillButton(isOn: Binding<Bool>, icon: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
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

            if np.queueSongs.count > 1 {
                Button {
                    let current = np.queueSongs[np.queueIndex]
                    np.queueSongs = [current]
                    np.queueIndex = 0
                } label: {
                    Text("Clear")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var emptyQueueRow: some View {
        HStack {
            Spacer()
            Text("No upcoming songs")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Actions

    private func playSong(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        np.lastManualSkipTime = Date()
        np.queueIndex = index
        let song = np.queueSongs[index]
        np.update(title: song.title, artist: song.artists.map(\.name).joined(separator: ", "), videoId: song.videoId, artists: song.artists)
        Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId) }
    }

    private func removeSong(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        np.queueSongs.remove(at: index)
        if let newIdx = np.queueSongs.firstIndex(where: { $0.videoId == np.videoId }) {
            np.queueIndex = newIdx
        }
    }
}

// MARK: - Queue Song Row

struct QueueSongRow: View {
    let song: SongItem
    var onPlay: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                let artistStr = song.artists.map(\.name).joined(separator: ", ")
                if !artistStr.isEmpty {
                    Text(artistStr)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay?()
        }
    }
}
