//
//  DiscordSettingsView.swift
//  Trop
//

import SwiftUI

struct DiscordSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var manager = DiscordRpcManager.shared
    @State private var showOAuth = false
    @State private var oauthURL: URL?
    @State private var isAuthorizing = false

    private let brand = IntegrationBrand.discord

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                statusCard
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                if manager.isAuthorized {
                    LabeledContent("Account") {
                        Text(manager.username ?? "Connected")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Gateway") {
                        Text(manager.connectionStatus.rawValue)
                            .foregroundStyle(gatewayColor)
                    }
                    Button("Log Out", role: .destructive) {
                        Task {
                            settings.discordRPCEnabled = false
                            await manager.logout()
                        }
                    }
                } else {
                    Button {
                        Task { await startAuthorize() }
                    } label: {
                        Label("Log In with Discord", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(manager.clientId.isEmpty || isAuthorizing)
                }
            } header: {
                Text("Account")
            } footer: {
                if manager.clientId.isEmpty {
                    Text("Add DiscordClientID to Trop.plist and register redirect trop://oauth2/callback in the Discord Developer Portal.")
                } else {
                    Text("Uses PKCE OAuth2 and classic gateway Rich Presence. Tokens stay in the Keychain.")
                }
            }

            Section {
                SettingsToggleRow(
                    "Enable Rich Presence",
                    icon: "antenna.radiowaves.left.and.right",
                    isOn: Binding(
                        get: { settings.discordRPCEnabled },
                        set: { newValue in
                            settings.discordRPCEnabled = newValue
                            Task {
                                if newValue {
                                    await manager.connectIfAuthorized()
                                } else {
                                    await manager.disconnect()
                                }
                            }
                        }
                    )
                )
                .disabled(!manager.isAuthorized)
            } header: {
                Text("Presence")
            } footer: {
                Text("When enabled, Trop updates your Discord listening activity as you play.")
            }

            if let error = manager.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Discord")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .sheet(isPresented: $showOAuth) {
            if let oauthURL {
                DiscordOAuthWebView(authURL: oauthURL) {
                    showOAuth = false
                    DiscordAuth.cancelPending()
                    isAuthorizing = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .discordAuthPresentWebView)) { note in
            if let url = note.userInfo?["url"] as? URL {
                oauthURL = url
                showOAuth = true
            }
        }
        .onAppear {
            if settings.discordRPCEnabled, manager.isAuthorized {
                Task { await manager.connectIfAuthorized() }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [brand.color, brand.color.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 22, weight: .semibold))
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

                Circle()
                    .fill(gatewayColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: gatewayColor.opacity(0.55), radius: 4)
            }

            if manager.isAuthorized {
                HStack(spacing: 10) {
                    Label(manager.username ?? "Discord", systemImage: "person.fill")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text(manager.connectionStatus.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gatewayColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(gatewayColor.opacity(0.14))
                        )
                }
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
        if manager.isAuthorized, settings.discordRPCEnabled,
           manager.connectionStatus == .connected {
            return "Presence live"
        }
        if manager.isAuthorized, settings.discordRPCEnabled {
            return "Connecting…"
        }
        if manager.isAuthorized {
            return "Signed in"
        }
        return "Connect Discord"
    }

    private var statusDetail: String {
        if manager.isAuthorized, settings.discordRPCEnabled,
           manager.connectionStatus == .connected {
            return "Listening activity updates while you play"
        }
        if manager.isAuthorized, settings.discordRPCEnabled {
            return "Waiting for the Discord gateway"
        }
        if manager.isAuthorized {
            return "Enable Rich Presence to go live"
        }
        return "Sign in with PKCE OAuth to show Rich Presence"
    }

    private var gatewayColor: Color {
        switch manager.connectionStatus {
        case .connected:
            return Color(red: 0.18, green: 0.72, blue: 0.32)
        case .connecting, .authorizing:
            return Color(red: 0.98, green: 0.70, blue: 0.15)
        case .disconnected:
            return Color(.tertiaryLabel)
        }
    }

    private func startAuthorize() async {
        isAuthorizing = true
        defer { isAuthorizing = false }
        do {
            try await manager.authorize()
            settings.discordRPCEnabled = true
            showOAuth = false
        } catch {
            showOAuth = false
            Log.discord.error("Discord authorize failed: \(error.localizedDescription)")
        }
    }
}
