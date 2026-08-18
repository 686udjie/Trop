//
//  MiniPlayerScrollState.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Shared state driving the mini player's compact-on-scroll behavior.
/// When the underlying content is scrolled down, the floating pill collapses
/// into a slim full-width bar (mirroring LNPopup's compact style).
@Observable
final class MiniPlayerScrollState {
    var isCompacted = false
}

/// Tracks a scroll container's vertical offset and flips `MiniPlayerScrollState.isCompacted`
/// with a small hysteresis so the mini player doesn't flicker at the top.
struct MiniPlayerCompactOnScrollModifier: ViewModifier {
    @Environment(MiniPlayerScrollState.self) private var scrollState

    private let compactThreshold: CGFloat = 30
    private let restoreThreshold: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: { $0.contentOffset.y }
            ) { _, newOffset in
                if newOffset > compactThreshold {
                    guard !scrollState.isCompacted else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        scrollState.isCompacted = true
                    }
                } else if newOffset <= restoreThreshold {
                    guard scrollState.isCompacted else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        scrollState.isCompacted = false
                    }
                }
            }
    }
}

extension View {
    /// Collapses the mini player into its compact bar while this scroll container
    /// is scrolled down past the top.
    func miniPlayerCompactsOnScroll() -> some View {
        modifier(MiniPlayerCompactOnScrollModifier())
    }
}