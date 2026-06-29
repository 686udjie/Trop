//
//  ContentView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import SwiftUI
import Combine

struct ContentView: View {
    @State private var resultText = ""
    @StateObject private var loginModel = LoginViewModel()
    @State private var isLoggedIn = false

    private let cookieStore = CookieStore()
    @State private var lastResult: PlaybackResult?

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                Text(resultText)
                    .font(.system(.caption, design: .monospaced))
            }

            HStack(spacing: 12) {
                // Login / account status button
                Button(isLoggedIn ? "Account" : "Login") {
                    if isLoggedIn {
                        Task { await testAccountMenu() }
                    } else {
                        loginModel.isPresented = true
                    }
                }
                .buttonStyle(.bordered)

                Button("Test /browse") {
                    Task { await testBrowse() }
                }
                .buttonStyle(.borderedProminent)

                Button("Resolve & Play") {
                    Task { await testResolveAndPlay() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .sheet(isPresented: $loginModel.isPresented) {
            NavigationStack {
                LoginWebView(model: loginModel)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { loginModel.isPresented = false }
                        }
                    }
            }
        }
        .onChange(of: loginModel.isLoggedIn) { _, loggedIn in
            // Save auth state when login succeeds
            if loggedIn {
                cookieStore.save(
                    cookies: loginModel.cookies,
                    sapisid: loginModel.sapisid,
                    visitorData: loginModel.visitorData
                )
                isLoggedIn = true
                Task { await InnerTube.shared.loadState(from: cookieStore) }
            }
        }
        .onAppear {
            // Restore persisted auth state on launch
            isLoggedIn = cookieStore.isLoggedIn
            if isLoggedIn {
                Task { await InnerTube.shared.loadState(from: cookieStore) }
            }
        }
    }

    // Calls InnerTube /browse and displays the response
    private func testBrowse() async {
        resultText = "Calling /browse..."
        do {
            let json = try await InnerTube.shared.browse(
                browseId: "FEmusic_home"
            )
            if let responseContext = json["responseContext"] {
                resultText = "SUCCESS\n\nresponseContext: \(responseContext)\n\nFull keys: \(json.keys.sorted())"
            } else {
                resultText = "Unexpected response:\n\(json)"
            }
        } catch {
            resultText = "Error: \(error.localizedDescription)"
        }
    }

    // Verifies logged-in state by fetching account menu
    private func testAccountMenu() async {
        resultText = "Fetching account..."
        do {
            let json = try await InnerTube.shared.accountMenu()
            resultText = "Account response:\n\(json)"
        } catch {
            resultText = "Account error: \(error.localizedDescription)"
        }
    }

    // Resolves a stream URL and plays via mpv
    private func testResolveAndPlay() async {
        resultText = "Initializing session..."
        do {
            try await InnerTube.shared.ensureVisitorData()
        } catch {
            print("[ContentView] Visitor data error: \(error.localizedDescription)")
        }

        resultText = "Resolving and playing..."
        let videoIds = ["eVTXPUF4Oz4", "dQw4w9WgXcQ"]

        for videoId in videoIds {
            do {
                let result = try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
                lastResult = result
                resultText = """
                Playing ✅
                Title: \(result.title ?? "?")
                Artist: \(result.author ?? "?")
                Client: \(result.clientName)
                Bitrate: \(result.bitrate) bps
                """
                return
            } catch {
                resultText = "\(videoId) failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
