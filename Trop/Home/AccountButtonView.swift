//
//  AccountButtonView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct AccountButtonView: View {
    var isLoggedIn: Bool
    var accountImageUrl: String?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if isLoggedIn {
                AsyncImageView(url: accountImageUrl)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            } else {
                fallback
            }
        }
        .buttonStyle(.plain)
    }

    private var fallback: some View {
        Circle()
            .fill(Color(.systemGray4))
            .frame(width: 28, height: 28)
            .overlay(
                Text("T")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            )
    }
}
