//
//  LastFMSettingsView.swift
//  Trop
//

import SwiftUI

struct LastFMSettingsView: View {
    @State private var settings = SettingsStore.shared
    @State private var service = LastFMService.shared
    @State private var showCredentialsWebView = false
    @State private var showLogin = false
    @State private var username = ""
    @State private var password = ""
    @State private var loginError: String?
    @State private var isLoggingIn = false
    @State private var manualAPIKey = ""
    @State private var manualSecret = ""
    @State private var showManualCredentials = false

    var body: some View {
        List {
            Section {
                if service.hasAPICredentials {
                    Label("API credentials saved", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add your Last.fm API key and shared secret to enable scrobbling.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Get API Credentials") {
                    showCredentialsWebView = true
                }
                Button("Enter Manually") {
                    showManualCredentials = true
                }
            } header: {
                Text("API Application")
            } footer: {
                Text("Opens last.fm so Trop can read your API Key and Shared secret after you create or view an API account.")
            }

            Section {
                if service.isLoggedIn {
                    LabeledContent("Signed in as") {
                        Text(service.username ?? "—")
                    }
                    Button("Log Out", role: .destructive) {
                        try? service.logout()
                        settings.lastFMEnabled = false
                    }
                } else {
                    Button("Log In") {
                        loginError = nil
                        showLogin = true
                    }
                    .disabled(!service.hasAPICredentials)
                }
            } header: {
                Text("Account")
            }

            Section {
                SettingsToggleRow("Enable Scrobbling", icon: "dot.radiowaves.left.and.right", isOn: $settings.lastFMEnabled)
                    .disabled(!service.isLoggedIn)
                SettingsToggleRow("Update Now Playing", icon: "music.note", isOn: $settings.lastFMUpdateNowPlaying)
                    .disabled(!service.isLoggedIn || !settings.lastFMEnabled)
            } header: {
                Text("Scrobbling")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scrobble after \(Int(settings.lastFMScrobbleDelayPercent * 100))% of track")
                    Slider(
                        value: $settings.lastFMScrobbleDelayPercent,
                        in: 0.4...0.95,
                        step: 0.05
                    )
                    .tint(settings.accentColor)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minimum duration: \(Int(settings.lastFMMinSongDuration))s")
                    Slider(
                        value: $settings.lastFMMinSongDuration,
                        in: 15...120,
                        step: 5
                    )
                    .tint(settings.accentColor)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Max delay: \(Int(settings.lastFMScrobbleDelaySeconds))s")
                    Slider(
                        value: $settings.lastFMScrobbleDelaySeconds,
                        in: 30...480,
                        step: 10
                    )
                    .tint(settings.accentColor)
                }
            } header: {
                Text("Timing")
            } footer: {
                Text(
                    "A scrobble is sent once listening time reaches the track percentage "
                    + "(or the max delay), and at least the minimum duration."
                )
            }
        }
        .navigationTitle("Last.fm")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .sheet(isPresented: $showCredentialsWebView) {
            LastFMCredentialsWebView { apiKey, secret in
                Task {
                    try? await service.saveAPICredentials(apiKey: apiKey, apiSecret: secret)
                }
            }
        }
        .sheet(isPresented: $showManualCredentials) {
            NavigationStack {
                Form {
                    TextField("API Key", text: $manualAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Shared Secret", text: $manualSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("API Credentials")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showManualCredentials = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                try? await service.saveAPICredentials(
                                    apiKey: manualAPIKey,
                                    apiSecret: manualSecret
                                )
                                showManualCredentials = false
                            }
                        }
                        .disabled(
                            manualAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || manualSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
        }
        .alert("Last.fm Login", isPresented: $showLogin) {
            TextField("Username", text: $username)
            SecureField("Password", text: $password)
            Button("Cancel", role: .cancel) {}
            Button("Sign In") {
                Task { await performLogin() }
            }
        } message: {
            Text(loginError ?? "Sign in with your Last.fm username and password.")
        }
    }

    private func performLogin() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            try await service.login(username: username, password: password)
            password = ""
            settings.lastFMEnabled = true
            showLogin = false
        } catch {
            loginError = error.localizedDescription
            showLogin = true
        }
    }
}
