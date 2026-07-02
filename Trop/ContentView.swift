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

    var body: some View {
        TabView {
            Tab("Home", systemImage: "music.note.house.fill") {
                HomeScreenView()
            }

            Tab("Library", systemImage: "music.note.square.stack") {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                Color(.systemBackground)
                    .ignoresSafeArea()
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

#Preview {
    ContentView()
}
