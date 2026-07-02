//
//  ContentView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import SwiftUI

struct ContentView: View {

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
    }
}

#Preview {
    ContentView()
}
