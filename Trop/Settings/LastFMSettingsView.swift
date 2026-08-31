//
//  LastFMSettingsView.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import SwiftUI
import Combine

struct LastFMSettingsView: View {
    @AppStorage(LastFMDefaults.sessionKeyKey) private var sessionKey = ""
    @AppStorage(LastFMDefaults.usernameKey) private var username = ""
    @AppStorage(LastFMDefaults.scrobblingEnabledKey) private var scrobblingEnabled = false
    @AppStorage(LastFMDefaults.useNowPlayingKey) private var useNowPlaying = false
    @AppStorage(LastFMDefaults.useSendLikesKey) private var useSendLikes = false
    @AppStorage(LastFMDefaults.scrobbleMinDurationKey) private var minDuration = LastFMDefaults.defaultScrobbleMinDuration
    @AppStorage(LastFMDefaults.scrobbleDelayPercentKey)
    private var scrobbleDelayPercentStored: Double = Double(LastFMDefaults.defaultScrobbleDelayPercent)
    @AppStorage(LastFMDefaults.scrobbleDelaySecondsKey) private var scrobbleDelaySeconds = LastFMDefaults.defaultScrobbleDelaySeconds

    @State private var showWebView = false
    @State private var showMinDurationEditor = false
    @State private var showDelayPercentEditor = false
    @State private var showDelaySecondsEditor = false
    @State private var isBusy = false
    @State private var lastError: String?
    @State private var avatarURL: URL?
    @State private var avatarLoading = false

    private var isLoggedIn: Bool { !sessionKey.isEmpty }

    var body: some View {
        List {
            // Login / Profile — top cell handles both states (mirrors Discord)
            Section("Account") {
                if isLoggedIn {
                    HStack(spacing: 14) {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.red)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(username.isEmpty ? "Last.fm User" : username).font(.headline)
                            Text(username.isEmpty ? "Connected to Last.fm" : "@\(username)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Logout", role: .destructive) {
                            LastFMIntegration.shared.logout()
                            sessionKey = ""
                            username = ""
                            avatarURL = nil
                            lastError = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                    .padding(.vertical, 4)

                    if let err = lastError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not logged in").font(.headline)
                            Text("Connect to enable scrobbling").font(.caption).foregroundStyle(.secondary)
                            if let err = lastError {
                                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                            } else if isBusy {
                                Text("Authorizing…").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isBusy {
                            ProgressView()
                        } else {
                            Button("Login") {
                                lastError = nil
                                isBusy = true
                                showWebView = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Enable Scrobbling", isOn: $scrobblingEnabled)
                    .disabled(!isLoggedIn)
                Toggle("Now Playing", isOn: $useNowPlaying)
                    .disabled(!isLoggedIn || !scrobblingEnabled)
                Toggle("Sync Likes to Last.fm", isOn: $useSendLikes)
                    .disabled(!isLoggedIn)
            } header: {
                Text("Options")
            } footer: {
                Text("Now Playing sends track.start when playback begins. Likes sync with track.love/unlove.")
            }

            Section {
                Button {
                    showMinDurationEditor = true
                } label: {
                    HStack {
                        Text("Minimum Track Duration")
                        Spacer()
                        Text(formatDuration(minDuration)).foregroundStyle(.secondary)
                    }
                }
                .disabled(!scrobblingEnabled)

                Button {
                    showDelayPercentEditor = true
                } label: {
                    HStack {
                        Text("Scrobble Percent")
                        Spacer()
                        Text("\(Int(scrobbleDelayPercent*100))%").foregroundStyle(.secondary)
                    }
                }
                .disabled(!scrobblingEnabled)

                Button {
                    showDelaySecondsEditor = true
                } label: {
                    HStack {
                        Text("Scrobble Delay Limit")
                        Spacer()
                        Text(formatDuration(scrobbleDelaySeconds)).foregroundStyle(.secondary)
                    }
                }
                .disabled(!scrobblingEnabled)
            } header: {
                Text("Scrobble Configuration")
            } footer: {
                // swiftlint:disable:next line_length
                Text("Scrobble after \(Int(scrobbleDelayPercent*100))% of track or \(formatDuration(scrobbleDelaySeconds)), whichever comes first. Tracks shorter than \(formatDuration(minDuration)) are ignored.")
            }
        }
        .navigationTitle("Last.fm")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWebView) {
            LastFMAuthWebView { success in
                isBusy = false
                if success {
                    sessionKey = LastFMTokenStore.shared.retrieveSessionKey() ?? ""
                    username = LastFMTokenStore.shared.retrieveUsername() ?? ""
                    lastError = nil
                    Task { await fetchAvatar() }
                }
            }
        }
        .onChange(of: showWebView) { _, isPresented in
            if !isPresented {
                isBusy = false
            }
        }
        .alert("Minimum Duration", isPresented: $showMinDurationEditor) {
            TextField("Seconds", value: $minDuration, format: .number)
                .keyboardType(.numberPad)
            Button("OK") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tracks shorter than this will not be scrobbled (10–60s).")
        }
        .alert("Scrobble Percent", isPresented: $showDelayPercentEditor) {
            // Map percent 30–95 via integer 30...95
            let binding = Binding<Double>(
                get: { scrobbleDelayPercentStored * 100 },
                set: { scrobbleDelayPercentStored = $0 / 100 }
            )
            // Use custom view not possible in alert; fallback to text field
            TextField("Percent (30–95)", value: binding, format: .number)
                .keyboardType(.numberPad)
            Button("OK") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Percentage of track to play before scrobbling.")
        }
        .alert("Scrobble Delay", isPresented: $showDelaySecondsEditor) {
            TextField("Seconds", value: $scrobbleDelaySeconds, format: .number)
                .keyboardType(.numberPad)
            Button("OK") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Maximum delay before scrobbling (30–360s).")
        }
        .onAppear {
            if UserDefaults.standard.object(forKey: LastFMDefaults.sessionKeyKey) == nil,
               let sk = LastFMTokenStore.shared.retrieveSessionKey() {
                sessionKey = sk
                username = LastFMTokenStore.shared.retrieveUsername() ?? ""
            }
        }
        .task {
            await fetchAvatar()
        }
        .onChange(of: username) { _, _ in
            Task { await fetchAvatar() }
        }
    }

    private var scrobbleDelayPercent: Double {
        scrobbleDelayPercentStored
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    private func fetchAvatar() async {
        guard isLoggedIn, !username.isEmpty else { return }
        if avatarLoading { return }
        avatarLoading = true
        defer { avatarLoading = false }
        if let url = await LastFMService.shared.fetchAvatarURL(username: username) {
            await MainActor.run { self.avatarURL = url }
        }
    }
}
