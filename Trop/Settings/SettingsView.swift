//
//  SettingsView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsNavigationRow("Appearance", icon: "paintpalette") {
                    AppearanceSettingsView()
                }
            } header: {
                Text("Appearance")
            }

            Section {
                SettingsNavigationRow("Player", icon: "play.circle") {
                    PlayerSettingsView()
                }
                SettingsNavigationRow("Downloads", icon: "arrow.down.circle") {
                    DownloadSettingsView()
                }
            } header: {
                Text("Playback & Offline")
            }

            Section {
                SettingsNavigationRow("Content", icon: "globe") {
                    ContentSettingsView()
                }
                SettingsNavigationRow("Lyrics", icon: "text.quote") {
                    LyricsSettingsView()
                }
            } header: {
                Text("Player & Content")
            }

            Section {
                SettingsNavigationRow("Integrations", icon: "link") {
                    IntegrationsSettingsView()
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Last.fm scrobbling and Discord Rich Presence.")
            }

            Section {
                SettingsNavigationRow("About", icon: "info.circle") {
                    AboutSettingsView()
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
