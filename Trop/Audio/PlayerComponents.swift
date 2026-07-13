//
//  PlayerComponents.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import SwiftUI

// MARK: - ProgressBar
struct ProgressBar: View {
    @Binding var progress: Float
    let accentColor: Color
    let isPlaying: Bool
    let onEditingChanged: (Bool) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let elapsedWidth = max(0, min(width, width * CGFloat(progress)))
            
            ZStack(alignment: .leading) {
                // Remaining track (unwatched)
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: 6)
                
                // Elapsed track (watched, marked)
                Capsule()
                    .fill(.white.opacity(0.8))
                    .frame(width: elapsedWidth, height: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onEditingChanged(true)
                        let loc = value.location.x
                        let percent = max(0, min(1, loc / width))
                        progress = Float(percent)
                    }
                    .onEnded { value in
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 12)
    }
}

// MARK: - PlaybackControlsRow
struct PlaybackControlsRow: View {
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!hasPrevious)
            .opacity(hasPrevious ? 1 : 0.3)
            .frame(maxWidth: .infinity)
            
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)
            .frame(maxWidth: .infinity)
            
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!hasNext)
            .opacity(hasNext ? 1 : 0.3)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - SecondaryActionsRow
struct SecondaryActionsRow: View {
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    let onRepeat: () -> Void
    @State private var isRepeatActive = false
    
    var body: some View {
        HStack(spacing: 0) {
            
            Button {
                showLyrics.toggle()
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(showLyrics ? .white : .white.opacity(0.7))
                    .padding(10)
                    .background(showLyrics ? Circle().fill(.white.opacity(0.15)) : Circle().fill(.clear))
            }
            .frame(maxWidth: .infinity)
            
            Button {
                // airplay
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            
            // Queue + Repeat stacked like Apple Music
            ZStack(alignment: .topTrailing) {
                Button {
                    showQueue.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(showQueue ? .white : .white.opacity(0.7))
                        .padding(10)
                        .background(showQueue ? Circle().fill(.white.opacity(0.15)) : Circle().fill(.clear))
                }
                
                Button {
                    isRepeatActive.toggle()
                    onRepeat()
                } label: {
                    Image(systemName: isRepeatActive ? "repeat.1" : "repeat")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isRepeatActive ? .white : .white.opacity(0.7))
                        .padding(4)
                        .background(
                            Circle()
                                .fill(isRepeatActive ? .white.opacity(0.25) : .white.opacity(0.1))
                        )
                }
                .offset(x: 2, y: -2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
    }
}

// MARK: - MarqueeText
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    private let leadingPause: Double = 2.2
    private let trailingPause: Double = 1.0
    private let speed: Double = 30

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animating = false

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Invisible reference text to get the true natural width
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { inner in
                            Color.clear.onAppear {
                                textWidth = inner.size.width
                                containerWidth = geo.size.width
                            }
                            .onChange(of: inner.size.width) { _, w in textWidth = w }
                            .onChange(of: text) { _, _ in textWidth = inner.size.width }
                        }
                    )

                // Visible scrolling text
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: offset)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            // Only fade the trailing edge
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: needsScroll ? 0.82 : 1),
                        .init(color: needsScroll ? .clear : .black, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                containerWidth = geo.size.width
                resetAndScroll()
            }
            .onChange(of: geo.size.width) { _, w in
                containerWidth = w
                resetAndScroll()
            }
        }
        .onChange(of: text) { _, _ in
            offset = 0
            animating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { resetAndScroll() }
        }
        .onChange(of: textWidth) { _, _ in resetAndScroll() }
    }

    private func resetAndScroll() {
        guard needsScroll else {
            offset = 0
            return
        }
        guard !animating else { return }
        animating = true

        let scrollDistance = textWidth - containerWidth
        let duration = scrollDistance / speed

        DispatchQueue.main.asyncAfter(deadline: .now() + leadingPause) {
            guard animating else { return }
            withAnimation(.linear(duration: duration)) {
                offset = -scrollDistance
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + trailingPause) {
                guard animating else { return }
                offset = 0
                animating = false
                resetAndScroll()
            }
        }
    }
}
