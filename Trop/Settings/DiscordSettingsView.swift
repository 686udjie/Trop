//
//  DiscordSettingsView.swift
//  Trop
//

import SwiftUI

struct DiscordSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var service = DiscordRpcService.shared
    @State private var showLogin = false
    @State private var applicationIdDraft = ""

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
                if service.isLoggedIn {
                    LabeledContent("Account") {
                        Text(service.username ?? "Connected")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Gateway") {
                        Text(service.connectionStatus.rawValue)
                            .foregroundStyle(gatewayColor)
                    }
                    Button("Log Out", role: .destructive) {
                        Task {
                            settings.discordRPCEnabled = false
                            await service.logout()
                        }
                    }
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label("Log In with Discord", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Uses classic gateway Rich Presence. Your session stays in the Keychain.")
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
                                    await service.connectIfNeeded()
                                } else {
                                    await service.disconnect()
                                }
                            }
                        }
                    )
                )
                .disabled(!service.isLoggedIn)
            } header: {
                Text("Presence")
            } footer: {
                Text("When enabled, Trop updates your Discord listening activity as you play.")
            }

            Section {
                TextField("Application ID", text: $applicationIdDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                    .onAppear {
                        applicationIdDraft = settings.discordApplicationId
                    }
                    .onChange(of: applicationIdDraft) { _, newValue in
                        settings.discordApplicationId = newValue
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
            } header: {
                Text("Discord Application")
            } footer: {
                Text("Create an application at the Discord Developer Portal and paste its Application ID for activity assets and naming.")
            }

            if let error = service.lastError {
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
        .sheet(isPresented: $showLogin) {
            DiscordLoginWebView { token, username in
                do {
                    try service.saveToken(token, username: username)
                    settings.discordRPCEnabled = true
                } catch {
                    Log.discord.error("Failed to save Discord token: \(error.localizedDescription)")
                }
            }
        }
        .onAppear {
            if settings.discordRPCEnabled, service.isLoggedIn {
                Task { await service.connectIfNeeded() }
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
                    .accessibilityLabel(service.connectionStatus.rawValue)
            }

            if service.isLoggedIn {
                HStack(spacing: 10) {
                    Label(service.username ?? "Discord", systemImage: "person.fill")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text(service.connectionStatus.rawValue)
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
        if service.isLoggedIn, settings.discordRPCEnabled,
           service.connectionStatus == .connected {
            return "Presence live"
        }
        if service.isLoggedIn, settings.discordRPCEnabled {
            return "Connecting…"
        }
        if service.isLoggedIn {
            return "Signed in"
        }
        return "Connect Discord"
    }

    private var statusDetail: String {
        if service.isLoggedIn, settings.discordRPCEnabled,
           service.connectionStatus == .connected {
            return "Listening activity updates while you play"
        }
        if service.isLoggedIn, settings.discordRPCEnabled {
            return "Waiting for the Discord gateway"
        }
        if service.isLoggedIn {
            return "Enable Rich Presence to go live"
        }
        return "Sign in to show classic Rich Presence"
    }

    private var gatewayColor: Color {
        switch service.connectionStatus {
        case .connected:
            return Color(red: 0.18, green: 0.72, blue: 0.32)
        case .connecting:
            return Color(red: 0.98, green: 0.70, blue: 0.15)
        case .disconnected:
            return Color(.tertiaryLabel)
        }
    }
}
