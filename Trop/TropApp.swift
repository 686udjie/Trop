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
    init() {
        configureNuke()
        ensureDirectories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Trop/Downloads"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Trop/Player"), withIntermediateDirectories: true)
    }
}
