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

                Button("Resolve Stream") {
                    Task { await testResolve() }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button("Play") {
                    guard let r = lastResult else {
                        resultText = "Resolve a stream first"
                        return
                    }
                    PlayerController.shared.play(url: r.streamUrl, title: r.title, artist: r.author)
                    resultText = "Playing..."
                }
                .buttonStyle(.borderedProminent)
                .disabled(lastResult == nil)
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

    // Resolves a stream URL for a test video using direct-URL clients
    private func testResolve() async {
        resultText = "Initializing session..."
        do {
            try await InnerTube.shared.ensureVisitorData()
            print("[ContentView] Visitor data ready")
        } catch {
            print("[ContentView] Failed to get visitor data: \(error.localizedDescription)")
        }

        resultText = "Resolving stream..."
        do {
            let videoIds = ["eVTXPUF4Oz4", "dQw4w9WgXcQ", "jfKfPfyJRdk"]
            var lastError: Error?
            var result: PlaybackResult?

            for videoId in videoIds {
                do {
                    result = try await StreamResolver.resolve(videoId: videoId, client: .androidVr1_43_32)
                    print("[ContentView] ✅ ANDROID_VR success for videoId=\(videoId)")
                    break
                } catch {
                    lastError = error
                    print("[ContentView] ANDROID_VR failed for \(videoId): \(error.localizedDescription)")
                }
                do {
                    result = try await StreamResolver.resolve(videoId: videoId, client: .iOS)
                    print("[ContentView] ✅ IOS success for videoId=\(videoId)")
                    break
                } catch {
                    lastError = error
                    print("[ContentView] IOS failed for \(videoId): \(error.localizedDescription)")
                }
            }

            guard let result else {
                throw lastError ?? StreamError.noStreams
            }
            lastResult = result
            let isValid = await StreamResolver.validateStream(url: result.streamUrl)
            resultText = """
            Resolved ✅
            Title: \(result.title ?? "?")
            Artist: \(result.author ?? "?")
            Client: \(result.clientName)
            Itag: \(result.itag)
            Quality: \(result.audioQuality)
            Bitrate: \(result.bitrate) bps
            MIME: \(result.mimeType)
            Expires: \(result.expiresInSeconds)s
            URL valid: \(isValid)
            URL: \(result.streamUrl.prefix(120))...
            """
        } catch {
            resultText = "Resolve error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
