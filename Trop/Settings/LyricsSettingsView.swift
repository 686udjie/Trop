//
//  LyricsSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct LyricsSettingsView: View {
    @State private var settings = SettingsStore.shared

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                ForEach(LyricsProviderRegistry.all, id: \.id) { provider in
                    Toggle(isOn: Binding(
                        get: { !settings.disabledLyricsProviders.contains(provider.id) },
                        set: { enabled in
                            var disabled = settings.disabledLyricsProviders
                            if enabled {
                                disabled.remove(provider.id)
                            } else {
                                disabled.insert(provider.id)
                            }
                            settings.disabledLyricsProviders = disabled
                        }
                    )) {
                        Label(provider.name, systemImage: "music.note")
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Disabled providers are skipped when fetching lyrics.")
            }

            Section {
                NavigationLink {
                    LyricsProviderOrderView()
                } label: {
                    Label("Provider Order", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("Lyrics")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}