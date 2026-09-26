//
//  MarqueeText.swift
//  Trop
//
//  Created by 686udjie on 17/07/2026.
//

import SwiftUI

struct MarqueeText: View {
    // MARK: - Public properties
    let text: String
    var font: Font = .body
    var frameHeight: CGFloat = 24
    var textColor: Color = .white

    // MARK: - State
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false
    @State private var animationTask: Task<Void, Never>?
    @State private var measuredWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    // MARK: - Constants
    private let fadeWidth: CGFloat = 12
    private let speed: CGFloat = 20            // points per second
    private let startDelay: UInt64 = 2_000_000_000
    private let endPause: UInt64 = 1_000_000_000
    private let overflowThreshold: CGFloat = 15

    private var overflow: CGFloat {
        max(0, measuredWidth - containerWidth)
    }

    private var shouldScroll: Bool {
        overflow > overflowThreshold
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            // MARK: - Single Text view
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .background(TextWidthReader())
                    .offset(x: offset)
                    .foregroundStyle(textColor)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .clipped()
            .mask(fadeMask(width: width))
            .onAppear {
                containerWidth = width
                ensureTask()
            }
            .onDisappear {
                stop()
            }
            .onChange(of: width) { _, newWidth in
                let wasScrolling = shouldScroll
                containerWidth = newWidth
                if wasScrolling != shouldScroll {
                    restart()
                }
            }
            .onPreferenceChange(TextWidthKey.self) { newWidth in
                // Ignore sub-point jitter — only restart on real overflow flips.
                guard abs(newWidth - measuredWidth) > 1 else { return }
                let wasScrolling = shouldScroll
                measuredWidth = newWidth
                if wasScrolling != shouldScroll {
                    restart()
                }
            }
        }
        .frame(height: frameHeight)
        .accessibilityLabel(text)
        .onChange(of: text) { oldText, newText in
            guard oldText != newText else { return }
            restart()
        }
    }

    // MARK: - Fade mask
    private func fadeMask(width: CGFloat) -> some View {
        let safe = max(width, 1)
        let trailingFade = shouldScroll ? min(fadeWidth, safe / 2) : 0
        let leadingFade = (shouldScroll && offset < 0) ? min(fadeWidth, safe / 2) : 0
        let start = leadingFade / safe
        let end = 1 - trailingFade / safe
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: start),
                .init(color: .black, location: end),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Animation task
    private func ensureTask() {
        // Never spin the infinite loop for non-overflowing text — this was
        // the "always-animating" churn: a task per MarqueeText that slept
        // 2s then re-checked forever even when nothing would scroll.
        guard shouldScroll, animationTask == nil else { return }
        startTask()
    }

    private func startTask() {
        animationTask?.cancel()
        // Static text needs no task at all.
        guard shouldScroll else {
            animationTask = nil
            resetOffset()
            return
        }
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                resetOffset()

                try? await Task.sleep(nanoseconds: startDelay)
                guard !Task.isCancelled else { break }

                guard shouldScroll else {
                    break
                }

                let distance = overflow + fadeWidth
                let duration = Double(distance / speed)

                isAnimating = true
                withAnimation(animationCurve(duration: duration)) {
                    offset = -distance
                }

                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { break }

                try? await Task.sleep(nanoseconds: endPause)
                guard !Task.isCancelled else { break }
            }
            if !Task.isCancelled {
                animationTask = nil
            }
        }
    }

    private func restart() {
        // Tearing down first avoids stacking tasks when width/text flaps.
        stop()
        ensureTask()
    }

    private func stop() {
        animationTask?.cancel()
        animationTask = nil
        resetOffset()
        isAnimating = false
    }

    // MARK: - Reset position
    private func resetOffset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
        }
        isAnimating = false
    }

    private func animationCurve(duration: Double) -> Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
    }
}

// MARK: - Measurement helpers
private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TextWidthReader: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: TextWidthKey.self, value: geo.size.width)
        }
    }
}
