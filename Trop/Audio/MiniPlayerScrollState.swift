//
//  MiniPlayerScrollState.swift
//  Trop
//
//  Created by 686udjie on 19/08/2026.
//

import SwiftUI

/// Shared state driving the mini player's inline (minimized) layout.
/// The system's `tabViewBottomAccessoryPlacement` environment can lag behind
/// the actual tab bar state on scroll-back, so the scroll containers set this
/// directly to keep the mini player's content in sync with its position.
@Observable
final class MiniPlayerScrollState {
    var isInline = false
}

/// Flips `MiniPlayerScrollState.isInline` based on a scroll container's vertical
/// offset, matching the system's tab bar minimize behavior: collapsing when the
/// user scrolls down and restoring the moment they scroll back up.
struct MiniPlayerInlineOnScrollModifier: ViewModifier {
    @Environment(MiniPlayerScrollState.self) private var scrollState

    private let compactThreshold: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: { $0.contentOffset.y }
            ) { oldOffset, newOffset in
                if newOffset > oldOffset, newOffset > compactThreshold {
                    guard !scrollState.isInline else { return }
                    scrollState.isInline = true
                } else if newOffset < oldOffset {
                    guard scrollState.isInline else { return }
                    scrollState.isInline = false
                }
            }
    }
}

extension View {
    /// Keeps the mini player's inline layout in sync with this scroll container:
    /// collapsing when scrolled down and restoring when back at the top.
    func miniPlayerTracksScroll() -> some View {
        modifier(MiniPlayerInlineOnScrollModifier())
    }
}
