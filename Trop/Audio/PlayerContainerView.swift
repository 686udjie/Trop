//
//  PlayerContainerView.swift
//  Trop
//
//  Created by 686udjie on 18/07/2026.
//

import SwiftUI

/// Hosts the app content alongside the native mini player bar and the
/// slide-up full player. Replaces the previous LNPopupUI popup system.
struct PlayerContainerView<Content: View>: View {
    let content: Content

    @Bindable private var np = NowPlaying.shared
    @State private var isExpanded = false
    @State private var scrollState = MiniPlayerScrollState()

    private let tabBarHeight: CGFloat = 49

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isExpanded {
                    FullPlayerView(onCollapse: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isExpanded = false
                        }
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                }

                if np.isBarPresented && !isExpanded {
                    if scrollState.isCompacted {
                        MiniPlayerCompactBarView(onExpand: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                isExpanded = true
                            }
                        })
                        .padding(.bottom, tabBarHeight + 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    } else {
                        MiniPlayerBarView(onExpand: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                isExpanded = true
                            }
                        })
                        .padding(.horizontal, 21)
                        .padding(.bottom, tabBarHeight + 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
            }
        }
        .environment(scrollState)
    }
}