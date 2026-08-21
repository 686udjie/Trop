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
    @Environment(SettingsStore.self) private var settings

    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    @Binding var isRepeatOn: Bool
    let pendingRoute: Binding<DetailRoute?>
    @ViewBuilder var progressSlider: () -> ProgressSlider

    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var activeIndex: Int = 0
    @State private var isFullscreen = false
    @State private var displayTime: TimeInterval = 0

    // MARK: - Auto-scroll & Re-sync

    @State private var isAutoScrollEnabled = true
    @State private var visibleLineID: LyricLine.ID?
    @State private var userHasScrolled = false
    @State private var scrollProxy: ScrollViewProxy?

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
        .task { await runDisplayTimer() }
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
                lyricsLoadingView
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
                lyricsContentView
            }
        }
    }

    // MARK: - Loading Spinner

    private var lyricsLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            Text(LyricsState.shared.providerName.map { "Lyrics from \($0)" } ?? "Searching for lyrics…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lyrics Content

    private var lyricsContentView: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: settings.lyricsAlignment.textAlignment.horizontal, spacing: 18) {
                        Spacer().frame(height: 24)

                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            LetterSyncLineView(
                                text: line.text,
                                isActive: index == activeIndex,
                                progress: progressForLine(at: index),
                                alignment: settings.lyricsAlignment,
                                fontSize: settings.lyricsFontSize,
                                lineOpacity: index == activeIndex ? 1 : opacityForDistance(abs(index - activeIndex)),
                                lineScale: index == activeIndex ? 1 : scaleForDistance(abs(index - activeIndex)),
                                onTap: {
                                    if let t = line.startTime {
                                        player.seek(to: t)
                                        np.currentTime = t
                                        resumeAutoScroll()
                                    }
                                }
                            )
                            .id(line.id)
                        }

                        Spacer().frame(height: 24)
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: $visibleLineID)
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .tracking || newPhase == .interacting {
                        pauseAutoScroll()
                    }
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: activeIndex) { _, newIndex in
                    guard lines.indices.contains(newIndex) else { return }
                    if isAutoScrollEnabled && !userHasScrolled {
                        scrollToActive()
                    }
                }
            }

            if userHasScrolled && !isLoading && !lines.isEmpty {
                resyncButton
            }
        }
    }

    // MARK: - Re-sync Button

    private var resyncButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                userHasScrolled = false
                isAutoScrollEnabled = true
            }
            scrollToActive()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                Text("Re-sync")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(.white.opacity(0.15)))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.bottom, 16)
    }

    // MARK: - Scrolling

    private func pauseAutoScroll() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAutoScrollEnabled = false
            userHasScrolled = true
        }
    }

    private func resumeAutoScroll() {
        isAutoScrollEnabled = true
        userHasScrolled = false
        scrollToActive()
    }

    /// Writing the scrollPosition binding cancels any in-flight user drag or
    /// deceleration; proxy.scrollTo then centers the active line.
    private func scrollToActive() {
        guard lines.indices.contains(activeIndex) else { return }
        let targetID = lines[activeIndex].id
        withAnimation(.easeInOut(duration: 0.4)) {
            visibleLineID = targetID
            scrollProxy?.scrollTo(targetID, anchor: .center)
        }
    }

    // MARK: - Distance-based Opacity & Scale (Metrolist-style)

    private func opacityForDistance(_ distance: Int) -> Double {
        switch distance {
        case 0: return 1
        case 1: return 0.7
        case 2: return 0.55
        default: return 0.4
        }
    }

    private func scaleForDistance(_ distance: Int) -> CGFloat {
        switch distance {
        case 0: return 1
        case 1: return 0.97
        default: return 0.94
        }
    }

    private func progressForLine(at index: Int) -> Double {
        guard lines.indices.contains(index), index == activeIndex else { return 0 }
        let line = lines[index]
        guard let start = line.startTime else { return 0 }

        // Use the actual next line's start time as end, like Metrolist does
        let end: TimeInterval
        if index + 1 < lines.count, let nextStart = lines[index + 1].startTime, nextStart > start {
            end = nextStart
        } else {
            let charCount = max(1, line.text.count)
            end = start + min(8, max(2, Double(charCount) * 0.08))
        }

        if displayTime < start { return 0 }
        if displayTime >= end { return 1 }
        let progress = (displayTime - start) / max(0.01, end - start)
        return min(1, max(0, progress))
    }

    /// Fires every 50 ms so letter-sync progress is smooth regardless of NowPlaying update rate.
    private func runDisplayTimer() async {
        while !Task.isCancelled {
            let t = np.currentTime
            if t != displayTime { displayTime = t }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Shared Song Info Row

    private func songInfoRow(showFullscreenButton: Bool) -> some View {
        HStack(spacing: 12) {
            if let uiImage = np.thumbnailUIImage {
                Image(uiImage: uiImage.centerCroppedSquare())
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

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: np.title,
                    font: .body.weight(.semibold),
                    frameHeight: 24
                )

                if !np.displayArtist.isEmpty {
                    Text(np.displayArtist)
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
            if np.queueSongs.indices.contains(np.queueIndex) {
                let currentSong = np.queueSongs[np.queueIndex]
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
            songInfoRow(showFullscreenButton: true)
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
        isAutoScrollEnabled = true
        userHasScrolled = false
        LyricsState.shared.providerName = nil

        // Keep waiting for lyrics — they can be matched/published late.
        // Retries every 15s until found or the song changes (.task(id:) cancels us).
        while !Task.isCancelled {
            do {
                let result = try await LyricsService.shared.fetchLyrics(videoId: videoId)
                if !result.isEmpty {
                    lines = result
                    isLoading = false
                    updateActiveLine()
                    return
                }
            } catch {
                // Keep waiting
            }
            try? await Task.sleep(for: .seconds(15))
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

// MARK: - Letter-by-Letter Sync Line View

private struct LetterSyncLineView: View {
    let text: String
    let isActive: Bool
    let progress: Double
    let alignment: LyricsAlignment
    let fontSize: Double
    var lineOpacity: Double = 1.0
    var lineScale: CGFloat = 1.0
    let onTap: () -> Void

    var body: some View {
        let textToDisplay = text.isEmpty ? "\u{266A}" : text

        Button(action: onTap) {
            Group {
                if isActive {
                    Text(revealedAttributedString(for: textToDisplay))
                        .font(.system(size: fontSize, weight: .bold))
                        .multilineTextAlignment(alignment.multilineTextAlignment)
                } else {
                    Text(textToDisplay)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(alignment.multilineTextAlignment)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment.textAlignment)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(lineOpacity)
        .scaleEffect(lineScale, anchor: alignment.textAlignment == .leading ? .leading : alignment.textAlignment == .trailing ? .trailing : .center)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    /// Builds an AttributedString where the first `revealedCount` characters are
    /// bright white and the remainder are dim — character-accurate, wrap-safe.
    private func revealedAttributedString(for string: String) -> AttributedString {
        let characters = Array(string)
        let total = characters.count
        let revealedCount = Int((Double(total) * max(0, min(1, progress))).rounded(.up))

        var result = AttributedString()
        for (i, char) in characters.enumerated() {
            var part = AttributedString(String(char))
            part.foregroundColor = i < revealedCount ? .white : UIColor(white: 1, alpha: 0.4)
            result.append(part)
        }
        return result
    }
}

private extension Alignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}
