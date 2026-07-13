//
//  ContentView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import SwiftUI
import LNPopupUI

struct ContentView: View {
    @State private var nowPlaying = NowPlaying.shared
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            if let accent = nowPlaying.accentColor {
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
            .popup(isBarPresented: .init(
                get: { nowPlaying.isBarPresented },
                set: { _ in }
            ), isPopupOpen: $nowPlaying.isPopupOpen) {
                MiniPlayerView()
            }
            .popupBarStyle(.floatingCompact)
            .popupBarProgressViewStyle(.bottom)
        }
    }
}

#Preview {
    ContentView()
}
