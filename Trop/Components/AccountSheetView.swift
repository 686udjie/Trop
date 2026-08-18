//
//  AccountSheetView.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Shared account sheet used by the Home and Library tabs.
struct AccountSheetView: View {
    var isLoggedIn: Bool
    var titleText: String
    var subtitleText: String
    var accountImageUrl: String?
    var onDone: () -> Void
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
                        .scaleEffect(1.3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleText)
                                .font(.headline)
                            if !subtitleText.isEmpty {
                                Text(subtitleText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if isLoggedIn {
                    Section {
                        Button(role: .destructive) {
                            onSignOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}