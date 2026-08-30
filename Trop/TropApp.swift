//
//  TropApp.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Nuke
import SwiftUI

@main
struct TropApp: App {
    @State private var settings = SettingsStore.shared

    init() {
        configureNuke()
        ensureDirectories()
        PlayerController.registerRemoteControlSupport()
        observePlaybackSettings()
        Task { @MainActor in DiscordIntegration.shared.start() }
    }

    /// Re-applies mpv playback settings whenever the user changes the
    /// equalizer or the audio filters from any screen.
    private func observePlaybackSettings() {
        func register() {
            withObservationTracking {
                let settings = SettingsStore.shared
                _ = settings.equalizerEnabled
                _ = settings.equalizerGains
                _ = settings.audioNormalization
                _ = settings.gaplessPlayback
            } onChange: {
                Task { @MainActor in
                    PlayerController.shared.applyPlaybackSettings()
                }
            }
        }
        register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.preferredColorScheme)
                .tint(settings.accentColor)
                .environment(settings)
                .environment(\.downloadManager, DownloadManager.shared)
        }
    }

    private func configureNuke() {
        let dataCache = try? DataCache(name: "com.trop.nuke")
        dataCache?.sizeLimit = 2 * 1024 * 1024 * 1024

        var config = ImagePipeline.Configuration()
        config.dataCache = dataCache
        config.imageCache = ImageCache(costLimit: 100 * 1024 * 1024)

        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    private func ensureDirectories() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Player"), withIntermediateDirectories: true)
    }
}
