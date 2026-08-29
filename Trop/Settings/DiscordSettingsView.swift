//
//  DiscordSettingsView.swift
//  Trop
//

import SwiftUI

struct DiscordSettingsView: View {
    @State private var settings = SettingsStore.shared
    @State private var service = DiscordRpcService.shared
    @State private var showLogin = false
    @State private var applicationIdDraft = ""

    var body: some View {
        List {
            Section {
                if service.isLoggedIn {
                    LabeledContent("Account") {
                        Text(service.username ?? "Connected")
                    }
                    LabeledContent("Status") {
                        Text(service.connectionStatus.rawValue)
                    }
                    Button("Log Out", role: .destructive) {
                        Task {
                            settings.discordRPCEnabled = false
                            await service.logout()
                        }
                    }
                } else {
                    Text("Sign in with Discord to show classic Rich Presence while you listen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Log In with Discord") {
                        showLogin = true
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Uses classic gateway Rich Presence (not Discord Social SDK). Your session stays in the Keychain.")
            }

            Section {
                SettingsToggleRow("Enable Rich Presence", icon: "antenna.radiowaves.left.and.right", isOn: Binding(
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
                ))
                .disabled(!service.isLoggedIn)
            } header: {
                Text("Presence")
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
                        settings.discordApplicationId = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
            } header: {
                Text("Discord Application")
            } footer: {
                Text("Create an application at the Discord Developer Portal and paste its Application ID. Used for activity assets and naming.")
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
}
