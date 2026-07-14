//
//  MiniPlayerView.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI
import LNPopupUI
import Marquee

struct MiniPlayerView: View {
    private let player = PlayerController.shared
    private let np = NowPlaying.shared

    @State private var editingProgress: Float = 0
    @State private var isEditingSlider = false
    @State private var activeItemId = ""
    
    @State private var isLiked = false
    @State private var showLyrics = false
    @State private var showQueue = false

    var body: some View {
        ZStack {
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
            
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                
                Spacer(minLength: 8)
                
                artwork
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
                    .padding(.horizontal, 32)
                
                Spacer(minLength: 16)
                
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
                    onRepeat: {}
                )
                
                Spacer(minLength: 8)
            }
        }
        .overlay(MiniPlayerPopupItems(
            queueSongs: np.queueSongs,
            videoId: np.videoId,
            isPlaying: np.isPlaying,
            thumbnailImage: np.thumbnailImage,
            thumbnailVersion: np.thumbnailVersion,
            activeItemId: $activeItemId
        ).equatable())
        .popupBarCustomizer { bar in
            bar.imageView.contentMode = .scaleAspectFill
            bar.imageView.cornerRadius = 6
        }
        .popupProgress(np.progress)
        .onChange(of: activeItemId) { _, newId in
            handleActiveItemChange(newId: newId)
        }
        .onChange(of: np.videoId) { _, newId in activeItemId = newId ?? "" }
        .onChange(of: np.queueSongs.count) { _, _ in activeItemId = np.videoId ?? "" }
    }

    private func handleActiveItemChange(newId: String) {
        guard newId != np.videoId else { return }
        guard let idx = np.queueSongs.firstIndex(where: { $0.videoId == newId }) else { return }
        np.lastManualSkipTime = Date()
        np.queueIndex = idx
        let song = np.queueSongs[idx]
        np.update(title: song.title, artist: song.artists.map(\.name).joined(separator: ", "), videoId: song.videoId, artists: song.artists)
        Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId) }
    }

    private var titleAndActionsRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Marquee {
                    Text(np.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .marqueeDirection(.right2left)
                .marqueeDuration(8.0)
                .marqueeWhenNotFit(true)
                .marqueeIdleAlignment(.leading)
                .frame(height: 28)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.92),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)

                let cleanedArtist = np.displayArtist
                if !cleanedArtist.isEmpty {
                    Marquee {
                        Text(cleanedArtist)
                            .font(.body)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .marqueeDirection(.right2left)
                    .marqueeWhenNotFit(true)
                    .marqueeDuration(8.0)
                    .marqueeIdleAlignment(.leading)
                    .frame(height: 20)
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    isLiked.toggle()
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isLiked ? .red : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                
                Button {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
            }
        }
    }

    private var artwork: some View {
        ZStack {
            if let img = np.thumbnailImage {
                GeometryReader { geo in
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(x: 1.35, y: 1.35, anchor: .center)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
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

private struct MiniPlayerPopupItems: View, Equatable {
    let queueSongs: [SongItem]
    let videoId: String?
    let isPlaying: Bool
    let thumbnailImage: Image?
    let thumbnailVersion: Int
    @Binding var activeItemId: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.videoId == rhs.videoId &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.queueSongs.map(\.videoId) == rhs.queueSongs.map(\.videoId) &&
        lhs.thumbnailVersion == rhs.thumbnailVersion
    }

    var body: some View {
        Color.clear
            .popupItems(selection: $activeItemId) {
                for song in queueSongs {
                    PopupItem(
                        id: song.videoId,
                        verbatimTitle: song.title,
                        verbatimSubtitle: song.artists.map { cleanArtistDisplay($0.name) }.filter { !$0.isEmpty }.joined(separator: ", "),
                        image: thumbnailImage,
                        progress: 0
                    ) {
                        ToolbarItemGroup(placement: .popupBar) {
                            Button(action: { PlayerController.shared.togglePlayPause() }) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                    }
                }
            }
    }
}
