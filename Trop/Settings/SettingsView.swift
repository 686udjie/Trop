//
//  SettingsView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct SettingsView: View {
    @State private var settings = LyricsSettings.shared
    @State private var order: [String] = LyricsSettings.shared.providerOrder

    private var providers: [LyricsProvider] {
        let ordered = order.compactMap { LyricsProviderRegistry.provider(for: $0) }
        let extra = LyricsProviderRegistry.all.filter { provider in
            !order.contains(provider.id)
        }
        return ordered + extra
    }

    var body: some View {
        List {
            Section {
                ForEach(providers, id: \.id) { provider in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(provider.name)
                        Spacer()
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("Lyrics Provider Fallback Order")
            } footer: {
                Text("Lyrics are fetched from the first provider in the list that returns results. Drag to reorder.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { order = settings.providerOrder }
        .onDisappear { settings.providerOrder = order }
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }
}
