//
//  CanvasSettingsView.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import SwiftUI

struct CanvasSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var showWebView = false
    @State private var isBusy = false
    @State private var lastError: String?
    @State private var profile: SpotifyProfile?
    @State private var hasSession = false

    private var isLoggedIn: Bool { profile != nil || hasSession }

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                if isLoggedIn {
                    HStack(spacing: 14) {
                        CachedAvatarView(url: profile?.avatarURL, size: 56)
                            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile?.displayName ?? "Spotify Connected").font(.headline)
                            if let profile {
                                Text("@\(profile.userId)").font(.subheadline).foregroundStyle(.secondary)
                                if let product = profile.product, !product.isEmpty {
                                    Text("Spotify \(product.capitalized)").font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Profile unavailable").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Logout", role: .destructive, action: logout)
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
                            Text("Connect to enable Spotify Canvas").font(.caption).foregroundStyle(.secondary)
                            if let err = lastError {
                                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                            } else if isBusy {
                                Text("Waiting for login…").font(.caption2).foregroundStyle(.secondary)
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
            } header: {
                Text("Account")
            }

            Section {
                Toggle("Spotify Canvas", isOn: $settings.canvasEnabled)
                    .disabled(!isLoggedIn)
                Toggle("Use cellular data", isOn: $settings.canvasOverCellular)
                    .disabled(!isLoggedIn)
            } header: {
                Text("Options")
            } footer: {
                Text("Plays the looping video behind the player artwork when Spotify has one for the track.")
            }
        }
        .navigationTitle("Spotify Canvas")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .sheet(isPresented: $showWebView) {
            SpotifyAuthWebView { success in
                isBusy = false
                if success {
                    refreshAccount()
                    lastError = nil
                }
            }
        }
        .onChange(of: showWebView) { _, isPresented in
            if !isPresented {
                isBusy = false
                refreshAccount()
            }
        }
        .onAppear {
            refreshAccount()
        }
    }

    private func refreshAccount() {
        profile = SpotifyAccountStore.shared.profile()
        hasSession = SpotifyAccountStore.shared.isLoggedIn
        // Sessions confirmed before the profile query existed carry a cookie
        // but no identity — backfill it when a bearer is at hand.
        guard profile == nil, hasSession else { return }
        Task {
            guard let token = await CanvasSpotifyToken.shared.accessToken() else { return }
            let client = await CanvasSpotifyToken.shared.clientToken()
            guard let fresh = await SpotifyCanvas.fetchProfileViaPathfinder(token: token, clientToken: client),
                  let cookie = SpotifyAccountStore.shared.cookie()
            else { return }
            SpotifyAccountStore.shared.store(cookie: cookie, profile: fresh)
            await MainActor.run { profile = fresh }
        }
    }

    private func logout() {
        SpotifyAccountStore.shared.clear()
        profile = nil
        hasSession = false
        lastError = nil
        Task {
            await CanvasSpotifyToken.shared.invalidate()
            await CanvasRepository.shared.clear()
            await SpotifyAccountStore.deleteWebCookies()
        }
    }
}
