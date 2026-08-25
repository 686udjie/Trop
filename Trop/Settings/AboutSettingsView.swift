//
//  AboutSettingsView.swift
//  Trop
//
//  Created by 686udjie on 26/08/2026.
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(version)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/686udjie/Trop")!) {
                    Text("GitHub")
                }
                Link(destination: URL(string: "https://discord.gg/QrMwZAfU97")!) {
                    Text("Discord")
                }
            } header: {
                Text("Links")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
