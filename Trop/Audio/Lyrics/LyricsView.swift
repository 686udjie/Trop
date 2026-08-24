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
    @State private var showSongMenu = false
    @State private var instrumentalGaps: [InstrumentalGap] = []
    @State private var allLines: [LyricLine] = []
    @State private var romanizedLines: [String?] = []

    struct InstrumentalGap {
        let afterIndex: Int
        let start: TimeInterval
        let end: TimeInterval
    }

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
        .sheet(isPresented: $showSongMenu) {
            LyricsMenuSheet()
        }
        .task(id: np.videoId) { await loadLyrics() }
        .onChange(of: np.currentTime) { _, _ in updateActiveLine() }
        .onChange(of: settings.lyricsOffsetSeconds) { _, _ in updateActiveLine() }
        .onChange(of: settings.romanizeCurrentTrack) { _, _ in
            Task { await rebuildRomanization() }
        }
        .onChange(of: LyricsState.shared.refreshToken) { _, _ in
            Task { await loadLyrics() }
        }
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
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: settings.lyricsAlignment.textAlignment.horizontal, spacing: 18) {
                            // Oversized insets so any line can be centered —
                            // Metrolist-style.
                            Spacer().frame(height: geo.size.height * 0.38)

                            if let provider = LyricsState.shared.providerName {
                                Text("Lyrics from \(provider)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: settings.lyricsAlignment.textAlignment)
                                    .padding(.horizontal, 24)
                            }

                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                lyricsLineRow(index: index, line: line)
                                    .id(line.id)
                            }

                            Spacer().frame(height: geo.size.height * 0.38)
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

    /// Centers the active line via the proxy only — writing the
    /// scrollPosition binding here would top-align the line and fight the
    /// center anchor.
    private func scrollToActive() {
        guard lines.indices.contains(activeIndex) else { return }
        let targetID = lines[activeIndex].id
        withAnimation(.easeInOut(duration: 0.4)) {
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
        let t = displayTime + settings.lyricsOffsetSeconds

        // Use the actual next line's start time as end, like Metrolist does
        var end: TimeInterval
        if index + 1 < lines.count, let nextStart = lines[index + 1].startTime, nextStart > start {
            end = nextStart
        } else {
            let charCount = max(1, line.text.count)
            end = start + min(8, max(2, Double(charCount) * 0.08))
        }

        // Hand the rest of the slot to the interval ring — the line's fill
        // finishes when the words end, never bleeding into instrumental time.
        if let gap = instrumentalGaps.last(where: { $0.afterIndex == index }) {
            let capped = min(end, gap.start)
            if capped > start { end = capped }
        }

        if t < start { return 0 }
        if t >= end { return 1 }
        let progress = (t - start) / max(0.01, end - start)
        return min(1, max(0, progress))
    }

    // MARK: - Interval Indicator (instrumental gaps)

    /// A lyric line plus its interval ring, which only exists in the hierarchy
    /// while playback is actually inside the gap.
    private func lyricsLineRow(index: Int, line: LyricLine) -> some View {
        let gap = instrumentalGaps.last(where: { $0.afterIndex == index })
        let showRing = settings.showIntervalIndicator && gap != nil && isVisibleInGap(gap!)
        let romanized = romanization(for: index)

        return VStack(spacing: 0) {
            LetterSyncLineView(
                text: line.text,
                isActive: index == activeIndex,
                progress: progressForLine(at: index),
                alignment: settings.lyricsAlignment,
                fontSize: settings.lyricsFontSize,
                lineOpacity: index == activeIndex ? 1 : opacityForDistance(abs(index - activeIndex)),
                lineScale: index == activeIndex ? 1 : scaleForDistance(abs(index - activeIndex)),
                romanizedText: romanized,
                onTap: {
                    if let t = line.startTime {
                        player.seek(to: t)
                        np.currentTime = t
                        resumeAutoScroll()
                    }
                }
            )

            if showRing, let gap {
                IntervalIndicatorView(
                    start: gap.start,
                    end: gap.end - 0.65,
                    now: displayTime + settings.lyricsOffsetSeconds,
                    color: intervalIndicatorColor
                )
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showRing)
    }

    /// Metrolist's expressiveAccent: white on dynamic (album art) backgrounds,
    /// the accent color on solid ones.
    private var intervalIndicatorColor: Color {
        switch settings.playerBackgroundStyle {
        case .solid: return settings.accentColor
        case .dynamic: return .white
        }
    }

    /// The romanized variant for a line, when the toggle is on and one exists.
    private func romanization(for index: Int) -> String? {
        guard settings.romanizeCurrentTrack,
              romanizedLines.indices.contains(index) else { return nil }
        return romanizedLines[index]
    }

    /// Blank / ♪-only timestamped lines declare instrumental spans.
    private static func isInstrumentalMarker(_ line: LyricLine) -> Bool {
        line.text.trimmingCharacters(in: CharacterSet(charactersIn: "♪*· "))
            .isEmpty
    }

    /// Mirrors Metrolist's updateMergedList: an interval ring is created only
    /// from positive evidence — a blank interlude marker whose timestamp says
    /// the words already ended. Nothing is estimated, so the ring never shows
    /// over actual singing.
    private func detectGaps(in all: [LyricLine]) -> [InstrumentalGap] {
        var displayIndices = [Int?](repeating: nil, count: all.count)
        var displayCount = 0
        for (i, line) in all.enumerated() where !Self.isInstrumentalMarker(line) {
            displayIndices[i] = displayCount
            displayCount += 1
        }

        var gaps: [InstrumentalGap] = []
        for (i, marker) in all.enumerated() {
            guard Self.isInstrumentalMarker(marker), let gapStart = marker.startTime else { continue }

            // Attach to the nearest preceding vocal line; intro markers have none.
            var afterIndex: Int?
            var j = i - 1
            while j >= 0, afterIndex == nil {
                afterIndex = displayIndices[j]
                j -= 1
            }
            guard let afterIndex else { continue }

            // The break ends when the next lyrics start.
            var nextStart: TimeInterval?
            var k = i + 1
            while k < all.count, nextStart == nil {
                nextStart = all[k].startTime
                k += 1
            }
            guard let gapEnd = nextStart, gapEnd - gapStart > 4 else { continue }

            gaps.append(InstrumentalGap(afterIndex: afterIndex, start: gapStart, end: gapEnd))
        }
        return gaps
    }

    /// The ring disappears slightly before vocals resume, like Metrolist's -650ms.
    private func isVisibleInGap(_ gap: InstrumentalGap) -> Bool {
        let t = displayTime + settings.lyricsOffsetSeconds
        return t >= gap.start && t <= gap.end - 0.65
    }

    // MARK: - Romanization

    /// Transliterates lines off the main actor when the toggle is on.
    private func rebuildRomanization() async {
        guard settings.romanizeCurrentTrack, !lines.isEmpty else {
            romanizedLines = []
            return
        }
        let texts = lines.map(\.text)
        romanizedLines = await Task.detached(priority: .userInitiated) {
            texts.map { LyricsRomanizer.romanize($0) }
        }.value
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
                    .scaledToFill()
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

    // MARK: - Fullscreen Bottom Row

    private var fullscreenBottomRow: some View {
        VStack(spacing: 6) {
            songInfoRow(showFullscreenButton: true)

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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
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
        allLines = []
        instrumentalGaps = []
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
                    let withoutMarkers = result.filter { !Self.isInstrumentalMarker($0) }
                    allLines = result
                    lines = withoutMarkers.isEmpty ? result : withoutMarkers
                    instrumentalGaps = detectGaps(in: result)
                    isLoading = false
                    updateActiveLine()
                    await rebuildRomanization()
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
        let t = np.currentTime + settings.lyricsOffsetSeconds
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

// MARK: - Interval Indicator Ring

/// Circular progress ring shown during instrumental gaps — SwiftUI take on
/// Metrolist's wavy ring: colored stroke over a 20% track.
///
/// Instead of stepping with playback-position updates (which arrive in coarse
/// chunks), the sweep is one continuous linear animation timed to finish
/// exactly when the gap ends; playback seeks re-anchor it.
private struct IntervalIndicatorView: View {
    let start: TimeInterval
    let end: TimeInterval
    let now: TimeInterval
    let color: Color

    @State private var displayedProgress: Double
    @State private var anchorNow: TimeInterval

    init(start: TimeInterval, end: TimeInterval, now: TimeInterval, color: Color) {
        self.start = start
        self.end = end
        self.now = now
        self.color = color
        _displayedProgress = State(initialValue: Self.fraction(at: now, start: start, end: end))
        _anchorNow = State(initialValue: now)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, min(1, displayedProgress))))
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 36, height: 36)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .onAppear { animateToCompletion() }
        .onChange(of: now) { _, newNow in
            // Position ticks are small; anything larger is a seek — re-anchor
            // the sweep so it still completes exactly on time.
            if abs(newNow - anchorNow) > 0.75 {
                anchorNow = newNow
                displayedProgress = Self.fraction(at: newNow, start: start, end: end)
                animateToCompletion(at: newNow)
            } else {
                anchorNow = newNow
            }
        }
    }

    private static func fraction(at t: TimeInterval, start: TimeInterval, end: TimeInterval) -> Double {
        guard end > start else { return 1 }
        return min(1, max(0, (t - start) / (end - start)))
    }

    private func animateToCompletion(at reference: TimeInterval? = nil) {
        let remaining = max(0.15, end - (reference ?? now))
        displayedProgress = min(displayedProgress, 0.999)
        withAnimation(.linear(duration: remaining).delay(0)) {
            displayedProgress = 1
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
    var lineOpacity: Double = 1
    var lineScale: CGFloat = 1
    /// Romanized variant rendered under the main line, Metrolist-style.
    var romanizedText: String?
    let onTap: () -> Void

    var body: some View {
        let textToDisplay = text.isEmpty ? "\u{266A}" : text

        Button(action: onTap) {
            VStack(alignment: alignment.textAlignment.horizontal, spacing: 4) {
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

                if let romanizedText, !romanizedText.isEmpty {
                    Text(romanizedText)
                        .font(.system(size: max(12, fontSize * 0.55), weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
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
