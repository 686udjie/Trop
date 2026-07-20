//
//  Log.swift
//  Trop
//
//  Created by 686udjie on 20/07/2026.
//

import OSLog

struct AppLogger {
    let logger: Logger

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.686udjie.Trop"

    static let player = AppLogger(logger: Logger(subsystem: subsystem, category: "Player"))
    static let mpv = AppLogger(logger: Logger(subsystem: subsystem, category: "mpv"))
    static let playbackManager = AppLogger(logger: Logger(subsystem: subsystem, category: "PlaybackManager"))
    static let nowPlaying = AppLogger(logger: Logger(subsystem: subsystem, category: "NowPlaying"))
    static let streamResolver = AppLogger(logger: Logger(subsystem: subsystem, category: "StreamResolver"))
    static let formatSelector = AppLogger(logger: Logger(subsystem: subsystem, category: "FormatSelector"))
    static let streamCache = AppLogger(logger: Logger(subsystem: subsystem, category: "StreamCache"))
    static let login = AppLogger(logger: Logger(subsystem: subsystem, category: "Login"))
    static let loginViewModel = AppLogger(logger: Logger(subsystem: subsystem, category: "LoginViewModel"))
    static let cipherWebView = AppLogger(logger: Logger(subsystem: subsystem, category: "CipherWebView"))
    static let cipher = AppLogger(logger: Logger(subsystem: subsystem, category: "Cipher"))
    static let cipherConfig = AppLogger(logger: Logger(subsystem: subsystem, category: "CipherConfig"))
    static let db = AppLogger(logger: Logger(subsystem: subsystem, category: "DB"))
    static let playlistDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "PlaylistDetail"))
    static let parser = AppLogger(logger: Logger(subsystem: subsystem, category: "Parser"))
    static let albumDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "AlbumDetail"))
    static let albumDetailViewModel = AppLogger(logger: Logger(subsystem: subsystem, category: "AlbumDetailViewModel"))
    static let artistDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "ArtistDetail"))
    static let podcastDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "PodcastDetail"))
    static let historyView = AppLogger(logger: Logger(subsystem: subsystem, category: "HistoryView"))
    static let homeScreenView = AppLogger(logger: Logger(subsystem: subsystem, category: "HomeScreenView"))
    static let homeViewModel = AppLogger(logger: Logger(subsystem: subsystem, category: "HomeViewModel"))
    static let libraryView = AppLogger(logger: Logger(subsystem: subsystem, category: "LibraryView"))
    static let innerTube = AppLogger(logger: Logger(subsystem: subsystem, category: "InnerTube"))
    static let playbackState = AppLogger(logger: Logger(subsystem: subsystem, category: "PlaybackState"))
    static let registerPlayback = AppLogger(logger: Logger(subsystem: subsystem, category: "RegisterPlayback"))
    static let poToken = AppLogger(logger: Logger(subsystem: subsystem, category: "PoToken"))
    static let search = AppLogger(logger: Logger(subsystem: subsystem, category: "Search"))
    static let searchView = AppLogger(logger: Logger(subsystem: subsystem, category: "SearchView"))
    static let downloadManager = AppLogger(logger: Logger(subsystem: subsystem, category: "DownloadManager"))
    static let sync = AppLogger(logger: Logger(subsystem: subsystem, category: "Sync"))
    static let addSong = AppLogger(logger: Logger(subsystem: subsystem, category: "AddSong"))
}
