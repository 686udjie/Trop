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
                SettingsNavigationRow("Player", icon: "play.circle") {
                    PlayerSettingsView()
                }
            } header: {
                Text("User Interface")
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
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}