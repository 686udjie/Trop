//
//  AccountSheetView.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Shared account sheet used by the Home and Library tabs.
struct AccountSheetView: View {
    @Environment(SettingsStore.self) private var settings

    var isLoggedIn: Bool
    var titleText: String
    var accountImageUrl: String?
    var onDone: () -> Void
    var onLogin: () -> Void
    var onSettings: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AccountButtonView(
                            isLoggedIn: isLoggedIn,
                            accountImageUrl: accountImageUrl,
                            onTap: {}
                        )
                        .scaleEffect(1.7)
                        .frame(width: 48, height: 48)

                        Text(titleText)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if isLoggedIn {
                            Button(action: onSignOut) {
                                centeredActionLabel(title: "Logout")
                            }
                            .buttonStyle(.bordered)
                            .tint(settings.accentColor)
                        } else {
                            Button(action: onLogin) {
                                centeredActionLabel(title: "Login")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(settings.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                Section {
                    Button(action: onSettings) {
                        HStack {
                            Label("Settings", systemImage: "gearshape")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func centeredActionLabel(title: String) -> some View {
        Text(title)
            .frame(width: 78)
    }
}