//
//  IntegrationsSettingsView.swift
//  Trop
//

import SwiftUI

struct IntegrationsSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsNavigationRow("Discord", icon: "gamecontroller") {
                    DiscordSettingsView()
                }
            } footer: {
                Text("Connect external services to enhance your experience.")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
