//
//  LastFMSettingsView.swift
//  Trop
//

import SwiftUI

struct LastFMSettingsView: View {
    @Environment(SettingsStore.self) private var settings
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

    private let brand = IntegrationBrand.lastFM

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                statusCard
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    showCredentialsWebView = true
                } label: {
                    Label("Get API Credentials", systemImage: "safari")
                }
                Button {
                    showManualCredentials = true
                } label: {
                    Label("Enter Manually", systemImage: "keyboard")
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
                            .foregroundStyle(.secondary)
                    }
                    Button("Log Out", role: .destructive) {
                        try? service.logout()
                        settings.lastFMEnabled = false
                    }
                } else {
                    Button {
                        loginError = nil
                        showLogin = true
                    } label: {
                        Label("Log In with Last.fm", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(!service.hasAPICredentials)
                }
            } header: {
                Text("Account")
            } footer: {
                if !service.hasAPICredentials {
                    Text("Add API credentials before signing in.")
                }
            }

            Section {
                SettingsToggleRow(
                    "Enable Scrobbling",
                    icon: "dot.radiowaves.left.and.right",
                    isOn: $settings.lastFMEnabled
                )
                .disabled(!service.isLoggedIn)
                SettingsToggleRow(
                    "Update Now Playing",
                    icon: "music.note",
                    isOn: $settings.lastFMUpdateNowPlaying
                )
                .disabled(!service.isLoggedIn || !settings.lastFMEnabled)
            } header: {
                Text("Scrobbling")
            }

            Section {
                timingSlider(
                    title: "Scrobble after \(Int(settings.lastFMScrobbleDelayPercent * 100))% of track",
                    value: $settings.lastFMScrobbleDelayPercent,
                    range: 0.4...0.95,
                    step: 0.05
                )
                timingSlider(
                    title: "Minimum duration: \(Int(settings.lastFMMinSongDuration))s",
                    value: $settings.lastFMMinSongDuration,
                    range: 15...120,
                    step: 5
                )
                timingSlider(
                    title: "Max delay: \(Int(settings.lastFMScrobbleDelaySeconds))s",
                    value: $settings.lastFMScrobbleDelaySeconds,
                    range: 30...480,
                    step: 10
                )
            } header: {
                Text("Timing")
            } footer: {
                Text(
                    "A scrobble is sent once listening time reaches the track percentage "
                    + "(or the max delay), and at least the minimum duration."
                )
            }

            if let error = service.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
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
            manualCredentialsSheet
        }
        .sheet(isPresented: $showLogin) {
            loginSheet
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [brand.color, brand.color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusHeadline)
                        .font(.title3.weight(.bold))
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                setupStep(number: 1, title: "API", done: service.hasAPICredentials)
                setupStep(number: 2, title: "Account", done: service.isLoggedIn)
                setupStep(number: 3, title: "Scrobble", done: service.isLoggedIn && settings.lastFMEnabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(brand.color.opacity(0.18), lineWidth: 1)
        )
    }

    private var statusHeadline: String {
        if service.isLoggedIn, settings.lastFMEnabled {
            return "Scrobbling on"
        }
        if service.isLoggedIn {
            return "Signed in"
        }
        if service.hasAPICredentials {
            return "Almost there"
        }
        return "Connect Last.fm"
    }

    private var statusDetail: String {
        if service.isLoggedIn, settings.lastFMEnabled {
            return "Plays sync to \(service.username ?? "your profile")"
        }
        if service.isLoggedIn {
            return "Enable scrobbling to start syncing plays"
        }
        if service.hasAPICredentials {
            return "Sign in with your Last.fm username and password"
        }
        return "Create or paste an API key, then sign in"
    }

    private func setupStep(number: Int, title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? brand.color : Color(.tertiarySystemFill))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(done ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(done ? brand.color.opacity(0.12) : Color(.tertiarySystemFill).opacity(0.55))
        )
    }

    private func timingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Slider(value: value, in: range, step: step)
                .tint(settings.accentColor)
        }
    }

    private var manualCredentialsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API Key", text: $manualAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Shared Secret", text: $manualSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("From last.fm/api/account — both values are 32-character hex strings.")
                }
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

    private var loginSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                } footer: {
                    Text(loginError ?? "Uses Last.fm’s mobile session API. Your password is not stored.")
                        .foregroundStyle(loginError == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Last.fm Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showLogin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign In") {
                        Task { await performLogin() }
                    }
                    .disabled(
                        isLoggingIn
                            || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || password.isEmpty
                    )
                }
            }
            .disabled(isLoggingIn)
        }
        .presentationDetents([.medium])
    }

    private func performLogin() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            try await service.login(username: username, password: password)
            password = ""
            settings.lastFMEnabled = true
            showLogin = false
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}
