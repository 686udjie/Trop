//
//  TabHeaderView.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Shared large-title header with history / settings / account buttons,
/// used by the Home and Library tabs.
struct TabHeaderView: View {
    let title: String
    var accountIsLoggedIn: Bool = false
    var accountImageUrl: String?
    var onHistory: () -> Void
    var onSettings: () -> Void
    var onAccount: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            HStack(spacing: 8) {
                Button(action: onHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("History")
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                AccountButtonView(
                    isLoggedIn: accountIsLoggedIn,
                    accountImageUrl: accountImageUrl,
                    onTap: onAccount
                )
                .accessibilityLabel("Account")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}