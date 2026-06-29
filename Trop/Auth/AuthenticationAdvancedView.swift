//
// AuthenticationAdvancedView.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import SwiftUI
import WebKit

// Exposes the underlying WKWebView so power users can inspect cookies / DOM
struct AuthenticationAdvancedView: View {
    @ObservedObject var webAuthentication: WebAuthentication

    var body: some View {
        List {
            Section("Active URL") {
                Text(webAuthentication.url?.absoluteString ?? "none")
                    .font(.system(.caption, design: .monospaced))
            }

            Section("Found cookies") {
                ForEach(Array(webAuthentication.cookies.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(webAuthentication.cookies[key] ?? "")
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .navigationTitle("Advanced")
        .onChange(of: webAuthentication.url) { _, _ in
            webAuthentication.extractCookies()
        }
    }
}
