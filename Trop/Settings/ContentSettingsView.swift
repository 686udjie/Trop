//
//  ContentSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct ContentSettingsView: View {
    @State private var settings = SettingsStore.shared

    private static let countries = ["US", "GB", "CA", "AU", "FR", "DE", "ES", "IT", "PT", "JP", "KR", "MX", "BR", "IN"]

    var body: some View {
        List {
            Section {
                SettingsToggleRow("Hide Explicit Content", icon: "eye.slash", isOn: $settings.hideExplicit)
            } header: {
                Text("Content Filtering")
            }

            Section {
                SettingsToggleRow("Show Quick Picks", icon: "sparkles", isOn: $settings.showQuickPicks)
                Stepper(value: $settings.topListsLength, in: 4...20, step: 2) {
                    Label("Top Lists Length: \(settings.topListsLength)", systemImage: "list.number")
                }
            } header: {
                Text("Home Feed")
            }

            Section {
                Picker("Country", selection: $settings.contentCountry) {
                    ForEach(Self.countries, id: \.self) { code in
                        Text(countryName(for: code)).tag(code)
                    }
                }
            } header: {
                Text("Region")
            } footer: {
                Text("Controls the region used for YouTube Music requests.")
            }
        }
        .navigationTitle("Content")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    private func countryName(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
