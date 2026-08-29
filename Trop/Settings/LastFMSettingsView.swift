//
//  LastFMSettingsView.swift
//  Trop
//

import SwiftUI

struct LastFMSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var scrobbler = LastFMScrobbler.shared
    @State private var showAuth = false
    @State private var authURL: URL?
    @State private var authToken: String?
    @State private var authError: String?

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
                if scrobbler.isLoggedIn {
                    LabeledContent("Signed in as") {
                        Text(scrobbler.username ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    Button("Log Out", role: .destructive) {
                        scrobbler.logout()
                    }
                } else {
                    Button {
                        Task { await startAuth() }
                    } label: {
                        Label("Connect Last.fm", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(!scrobbler.isConfigured || scrobbler.isBusy)
                }
            } header: {
                Text("Account")
            } footer: {
                if !scrobbler.isConfigured {
                    Text("Add LastFMAPIKey and LastFMAPISecret to Trop.plist to enable Last.fm.")
                } else {
                    Text("Opens last.fm so you can authorize Trop. Session key is stored in UserDefaults.")
                }
            }

            Section {
                SettingsToggleRow(
                    "Enable Scrobbling",
                    icon: "dot.radiowaves.left.and.right",
                    isOn: $settings.lastFMEnabled
                )
                .disabled(!scrobbler.isLoggedIn)
                SettingsToggleRow(
                    "Update Now Playing",
                    icon: "music.note",
                    isOn: $settings.lastFMUpdateNowPlaying
                )
                .disabled(!scrobbler.isLoggedIn || !settings.lastFMEnabled)
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
                Text("Default is 50% of the track or 180 seconds, whichever comes first (clamped by max delay).")
            }

            if let error = authError ?? scrobbler.lastError {
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
        .sheet(isPresented: $showAuth) {
            if let authURL, let authToken {
                LastFMAuthWebView(authURL: authURL, token: authToken) { result in
                    showAuth = false
                    switch result {
                    case .success(let auth):
                        Task { await scrobbler.completeAuthorization(auth) }
                    case .failure(let error):
                        authError = error.localizedDescription
                    }
                }
            }
        }
        .onAppear {
            scrobbler.restoreSession()
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
                setupStep(number: 1, title: "API", done: scrobbler.isConfigured)
                setupStep(number: 2, title: "Account", done: scrobbler.isLoggedIn)
                setupStep(number: 3, title: "Scrobble", done: scrobbler.isLoggedIn && settings.lastFMEnabled)
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
        if scrobbler.isLoggedIn, settings.lastFMEnabled { return "Scrobbling on" }
        if scrobbler.isLoggedIn { return "Signed in" }
        if scrobbler.isConfigured { return "Almost there" }
        return "Connect Last.fm"
    }

    private var statusDetail: String {
        if scrobbler.isLoggedIn, settings.lastFMEnabled {
            return "Plays sync to \(scrobbler.username ?? "your profile")"
        }
        if scrobbler.isLoggedIn {
            return "Enable scrobbling to start syncing plays"
        }
        if scrobbler.isConfigured {
            return "Authorize Trop on last.fm to continue"
        }
        return "Add API keys to Trop.plist, then connect"
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

    private func startAuth() async {
        authError = nil
        do {
            let pair = try await scrobbler.beginAuthorization()
            authURL = pair.url
            authToken = pair.token
            showAuth = true
        } catch {
            authError = error.localizedDescription
        }
    }
}
