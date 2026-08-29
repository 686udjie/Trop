//
//  IntegrationsSettingsView.swift
//  Trop
//

import SwiftUI

struct IntegrationsSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsNavigationRow("Last.fm", icon: "dot.radiowaves.left.and.right") {
                    LastFMSettingsView()
                }
                SettingsNavigationRow("Discord", icon: "bubble.left.and.bubble.right") {
                    DiscordSettingsView()
                }
            } header: {
                Text("Services")
            } footer: {
                Text("Scrobble to Last.fm and show what you're listening to on Discord with classic Rich Presence.")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
