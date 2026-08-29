//
//  IntegrationsSettingsView.swift
//  Trop
//

import SwiftUI

struct IntegrationsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var lastFM = LastFMService.shared
    @State private var discord = DiscordRpcService.shared

    var body: some View {
        List {
            Section {
                IntegrationServiceCard(
                    title: "Last.fm",
                    subtitle: lastFMStatusSubtitle,
                    systemImage: "waveform.circle.fill",
                    brand: IntegrationBrand.lastFM,
                    status: lastFMStatus,
                    accent: settings.accentColor
                ) {
                    LastFMSettingsView()
                }
                .listRowInsets(.init(top: 8, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                IntegrationServiceCard(
                    title: "Discord",
                    subtitle: discordStatusSubtitle,
                    systemImage: "bubble.left.and.bubble.right.fill",
                    brand: IntegrationBrand.discord,
                    status: discordStatus,
                    accent: settings.accentColor
                ) {
                    DiscordSettingsView()
                }
                .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } footer: {
                Text("Scrobble plays to Last.fm and show what you’re listening to with classic Discord Rich Presence.")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    private var lastFMStatus: IntegrationConnectionStatus {
        if lastFM.isLoggedIn, settings.lastFMEnabled { return .active }
        if lastFM.isLoggedIn { return .connected }
        if lastFM.hasAPICredentials { return .ready }
        return .setup
    }

    private var lastFMStatusSubtitle: String {
        switch lastFMStatus {
        case .active:
            return "Scrobbling as \(lastFM.username ?? "you")"
        case .connected:
            return "Signed in as \(lastFM.username ?? "you")"
        case .ready:
            return "API ready — sign in to scrobble"
        case .setup:
            return "Connect your Last.fm account"
        }
    }

    private var discordStatus: IntegrationConnectionStatus {
        if discord.isLoggedIn, settings.discordRPCEnabled,
           discord.connectionStatus == .connected {
            return .active
        }
        if discord.isLoggedIn, settings.discordRPCEnabled { return .ready }
        if discord.isLoggedIn { return .connected }
        return .setup
    }

    private var discordStatusSubtitle: String {
        switch discordStatus {
        case .active:
            return discord.username.map { "Live as \($0)" } ?? "Rich Presence live"
        case .connected:
            return discord.username.map { "Signed in as \($0)" } ?? "Signed in"
        case .ready:
            return discord.connectionStatus.rawValue
        case .setup:
            return "Show listening status on Discord"
        }
    }
}

// MARK: - Shared integration UI

enum IntegrationBrand {
    case lastFM
    case discord

    var color: Color {
        switch self {
        case .lastFM:
            return Color(red: 0.84, green: 0.06, blue: 0.03)
        case .discord:
            return Color(red: 0.35, green: 0.40, blue: 0.95)
        }
    }
}

enum IntegrationConnectionStatus {
    case setup
    case ready
    case connected
    case active

    var label: String {
        switch self {
        case .setup: return "Set up"
        case .ready: return "Ready"
        case .connected: return "Connected"
        case .active: return "Active"
        }
    }
}

private struct IntegrationServiceCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let brand: IntegrationBrand
    let status: IntegrationConnectionStatus
    let accent: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [brand.color, brand.color.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        statusChip
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(brand.color.opacity(status == .active ? 0.35 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .tint(accent)
    }

    private var statusChip: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status == .setup ? .secondary : brand.color)
            .background(
                Capsule(style: .continuous)
                    .fill(status == .setup
                          ? Color(.tertiarySystemFill)
                          : brand.color.opacity(0.14))
            )
    }
}
