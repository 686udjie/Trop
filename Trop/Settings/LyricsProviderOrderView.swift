//
//  LyricsProviderOrderView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct LyricsProviderOrderView: View {
    @State private var settings = LyricsSettings.shared
    @State private var order: [String] = LyricsSettings.shared.providerOrder

    private var providers: [LyricsProvider] {
        order.compactMap { LyricsProviderRegistry.provider(for: $0) }
    }

    var body: some View {
        List {
            ForEach(providers, id: \.id) { provider in
                Text(provider.name)
            }
            .onMove(perform: move)
        }
        .navigationTitle("Lyrics Providers")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .safeAreaInset(edge: .bottom) {
            Text("Drag to reorder providers")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .miniPlayerTracksScroll()
        .onAppear {
            var merged = settings.providerOrder
            for provider in LyricsProviderRegistry.all where !merged.contains(provider.id) {
                merged.append(provider.id)
            }
            order = merged
        }
        .onDisappear { settings.providerOrder = order }
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }
}