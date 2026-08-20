//
//  ContentView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var nowPlaying = NowPlaying.shared
    @State private var selectedTab = SettingsStore.shared.defaultTab
    @State private var isExpanded = false
    @State private var scrollState = MiniPlayerScrollState()

    var body: some View {
        ZStack {
            if settings.playerBackgroundStyle == .solid {
                Color.black.ignoresSafeArea()
            } else if let accent = nowPlaying.accentColor {
                accent
                    .opacity(0.06)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.8), value: nowPlaying.accentColor)
            }

            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "music.note.house.fill", value: 0) {
                    HomeScreenView()
                }

                Tab("Library", systemImage: "music.note.square.stack", value: 1) {
                    LibraryView()
                }

                Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                    SearchView(onExitSearch: { selectedTab = 0 })
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: nowPlaying.isBarPresented) {
                MiniPlayerBarView(onExpand: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded = true
                    }
                })
            }

            if isExpanded {
                FullPlayerView(onCollapse: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded = false
                    }
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .environment(scrollState)
    }
}

#Preview {
    ContentView()
}