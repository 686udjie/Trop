//
//  DownloadManager.swift
//  Trop
//
//  Created by 686udjie on 19/07/2026.
//

import AVFoundation
import Combine
import Foundation
import GRDB
import Network
import Nuke
import UIKit
import ffmpegkit

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var persistedDownloadCount: Int = 0

    enum DownloadState: Equatable {
        case notStarted
        case downloading(Double)
        case completed
        case failed(String)
    }

    enum DownloadSort: String, CaseIterable, Identifiable {
        case recent
        case title
        case artist

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .recent: return "Recent"
            case .title: return "Title"
            case .artist: return "Artist"
            }
        }
    }

    private let fileManager = FileManager.default
    private let pathMonitor = NWPathMonitor()
    private var currentPath: NWPath?
    private var downloadedVideoIds: Set<String> = []
    private var cancelledDownloadIds: Set<String> = []
    private var lastReportedProgress: [String: Double] = [:]
    private var downloadsDir: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Downloads")
    }

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.currentPath = path
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.trop.network"))
        Task { await refreshDownloadedCache() }
    }

    private var isOnWiFi: Bool {
        // Until the first path update arrives, don't block downloads.
        guard let currentPath else { return true }
        return currentPath.usesInterfaceType(.wifi) == true
            || currentPath.usesInterfaceType(.wiredEthernet) == true
    }

    /// AAC transcode bitrate for the download quality preference.
    nonisolated static func transcodeBitrate(for quality: DownloadQuality) -> Int {
        switch quality {
        case .auto, .high: return 192_000
        case .standard: return 96_000
        }
    }

    func download(song: SongItem) async {
        let videoId = song.videoId
        if case .downloading = downloads[videoId] {
            Log.downloadManager.debug("Download already in progress for \(videoId)")
            return
        }

        cancelledDownloadIds.remove(videoId)
        lastReportedProgress.removeValue(forKey: videoId)
        let artist = song.artists.map(\.name).joined(separator: ", ")
        let downloadStart = CFAbsoluteTimeGetCurrent()
        Log.downloadManager.debug("Starting download: \(artist) - \(song.title) (\(videoId))")

        if SettingsStore.shared.wifiOnlyDownloads, !isOnWiFi {
            downloads[videoId] = .failed("Wi-Fi Only is enabled and you are not on Wi-Fi.")
            objectWillChange.send()
            return
        }

        setProgress(0.02, for: videoId)

        do {
            let fileURL = downloadsDir.appendingPathComponent(
                sanitizedFileName("\(artist) - \(song.title).m4a")
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }

            async let artworkData = prefetchArtwork(from: song.thumbnailUrl)

            setProgress(0.05, for: videoId)
            let resolveStart = CFAbsoluteTimeGetCurrent()
            let result = try await PlaybackManager.shared.resolve(
                videoId: videoId,
                forDownload: true
            )
            let resolveElapsed = CFAbsoluteTimeGetCurrent() - resolveStart
            let streamURL = result.streamUrl
            let isAACStream = result.mimeType.lowercased().contains("mp4a")
                || result.mimeType.lowercased().contains("aac")
            Log.downloadManager.debug("RESOLVE \(String(format: "%.1f", resolveElapsed))s codec=\(result.mimeType) isAAC=\(isAACStream)")

            guard let url = URL(string: streamURL) else {
                throw DownloadError.invalidStreamURL
            }

            let tempDownload = fileManager.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(isAACStream ? "m4a" : "webm")")
            defer { try? fileManager.removeItem(at: tempDownload) }
            let dlStart = CFAbsoluteTimeGetCurrent()
            try await downloadToFile(
                from: url,
                to: tempDownload,
                videoId: videoId
            )
            let dlElapsed = CFAbsoluteTimeGetCurrent() - dlStart
            let dlSize = (try? tempDownload.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            Log.downloadManager.debug("DOWNLOAD \(String(format: "%.1f", dlElapsed))s \(dlSize / 1024)KB")

            let validateStart = CFAbsoluteTimeGetCurrent()
            try await validateDownloadedFile(at: tempDownload)
            Log.downloadManager.debug("VALIDATE \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - validateStart))s")

            let artwork = await artworkData

            ensureDirectories()
            setProgress(0.88, for: videoId)
            let ffmpegStart = CFAbsoluteTimeGetCurrent()
            if isAACStream {
                Log.downloadManager.debug("FFMPEG remux (AAC passthrough)...")
                try await attachMetadata(
                    to: tempDownload,
                    title: song.title,
                    artist: artist,
                    artworkData: artwork
                )
                try? fileManager.moveItem(at: tempDownload, to: fileURL)
            } else {
                Log.downloadManager.debug("FFMPEG transcode (Opus -> AAC)...")
                try await processAudio(
                    inputURL: tempDownload,
                    outputURL: fileURL,
                    title: song.title,
                    artist: artist,
                    artworkData: artwork
                )
            }
            Log.downloadManager.debug("FFMPEG \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - ffmpegStart))s")

            if cancelledDownloadIds.contains(videoId) {
                cancelledDownloadIds.remove(videoId)
                lastReportedProgress.removeValue(forKey: videoId)
                try? fileManager.removeItem(at: fileURL)
                downloads[videoId] = .notStarted
                objectWillChange.send()
                return
            }

            let entity = DownloadedTrackEntity(
                id: videoId,
                title: song.title,
                artist: artist,
                duration: song.duration,
                thumbnailUrl: song.thumbnailUrl,
                localPath: fileURL.path,
                downloadedAt: Date()
            )
            try await DatabaseService.shared.insertOrReplace(entity)
            downloadedVideoIds.insert(videoId)
            persistedDownloadCount = downloadedVideoIds.count

            downloads[videoId] = .completed
            lastReportedProgress.removeValue(forKey: videoId)
            let totalElapsed = CFAbsoluteTimeGetCurrent() - downloadStart
            Log.downloadManager.debug("DONE \(String(format: "%.1f", totalElapsed))s total: \(artist) - \(song.title)")
            objectWillChange.send()
        } catch {
            if cancelledDownloadIds.contains(videoId) || (error as? URLError)?.code == .cancelled {
                cancelledDownloadIds.remove(videoId)
                lastReportedProgress.removeValue(forKey: videoId)
                downloads[videoId] = .notStarted
                objectWillChange.send()
                return
            }
            downloads[videoId] = .failed(userFacingDownloadError(error))
            lastReportedProgress.removeValue(forKey: videoId)
            Log.downloadManager.error("Failed download \(videoId): \(error.localizedDescription)")
            objectWillChange.send()
        }
    }

    private func validateDownloadedFile(at url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        // Real audio streams are well above this; error/HTML bodies are not.
        guard size >= 8_192 else {
            Log.downloadManager.error("Downloaded file too small (\(size) bytes) — likely a dead stream URL")
            throw DownloadError.invalidStreamURL
        }

        let asset = AVURLAsset(url: url)
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            Log.downloadManager.error("Cannot open downloaded file as audio: \(error.localizedDescription)")
            throw DownloadError.invalidStreamURL
        }
        guard !audioTracks.isEmpty else {
            Log.downloadManager.error("Downloaded file has no audio track — rejecting as invalid stream")
            throw DownloadError.invalidStreamURL
        }
    }

    private func userFacingDownloadError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection."
            case .timedOut:
                return "The download timed out."
            default:
                break
            }
        }
        if let downloadError = error as? DownloadError {
            return downloadError.errorDescription ?? "Download failed. Try again."
        }
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            return "Could not process this track for offline playback. Try again."
        }
        return "Download failed. Try again."
    }

    private func refreshDownloadedCache() async {
        downloadedVideoIds = Set((await fetchAll()).map(\.id))
        persistedDownloadCount = downloadedVideoIds.count
    }

    static func shouldRefreshPersistedLibrary(
        old: [String: DownloadState],
        new: [String: DownloadState]
    ) -> Bool {
        for (videoId, newState) in new {
            let oldState = old[videoId] ?? .notStarted
            if oldState == newState { continue }
            switch (oldState, newState) {
            case (.downloading, .completed), (.downloading, .failed),
                 (.completed, .notStarted), (.failed, .notStarted),
                 (.notStarted, .completed):
                return true
            default:
                continue
            }
        }
        for (videoId, oldState) in old where new[videoId] == nil {
            if case .completed = oldState { return true }
        }
        return false
    }

    private func cancelAllActiveDownloads() {
        cancelledDownloadIds.removeAll()
    }

    private func setProgress(_ fraction: Double, for videoId: String) {
        let clamped = min(0.99, max(0, fraction))
        let last = lastReportedProgress[videoId] ?? -1
        guard clamped >= 0.99 || last < 0 || clamped - last >= 0.02 else { return }
        lastReportedProgress[videoId] = clamped
        downloads[videoId] = .downloading(clamped)
    }

    private func prefetchArtwork(from thumbnailUrl: String?) async -> Data? {
        guard let thumbUrl = thumbnailUrl, let url = URL(string: thumbUrl) else { return nil }
        guard let image = try? await ImagePipeline.shared.image(for: url) else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    private func downloadToFile(
        from url: URL,
        to destination: URL,
        videoId: String
    ) async throws {
        guard let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") else {
            throw NSError(domain: "DownloadManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "CA certificate bundle not found"])
        }

        let args = [
            "-y",
            "-cafile", caPath,
            "-headers", "User-Agent: Mozilla/5.0\r\n",
            "-i", url.absoluteString,
            "-c", "copy",
            destination.path
        ]

        let session = FFmpegKit.execute(withArguments: args)
        let rc = session?.getReturnCode() ?? ReturnCode(1)

        guard ReturnCode.isSuccess(rc) else {
            throw NSError(domain: "DownloadManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "FFmpeg download failed: \(session?.getOutput() ?? "")"])
        }
    }

    func delete(videoId: String) async {
        lastReportedProgress.removeValue(forKey: videoId)
        downloads[videoId] = .notStarted
        downloadedVideoIds.remove(videoId)
        persistedDownloadCount = downloadedVideoIds.count
        if let entity = try? await DatabaseService.shared.fetchOne(DownloadedTrackEntity.self, key: videoId) {
            try? fileManager.removeItem(atPath: entity.localPath)
            _ = try? await DatabaseService.shared.delete(entity)
        }
        objectWillChange.send()
    }

    func localURL(for videoId: String) -> URL? {
        guard let entity = try? DatabaseService.shared.dbPool.read({ db in
            try DownloadedTrackEntity.fetchOne(db, key: videoId)
        }) else { return nil }
        let url = URL(fileURLWithPath: entity.localPath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(videoId: String) -> Bool {
        downloadedVideoIds.contains(videoId)
    }

    func fetchAll() async -> [DownloadedTrackEntity] {
        (try? await DatabaseService.shared.fetchAll(DownloadedTrackEntity.self)) ?? []
    }

    func fetchAllSorted(by sort: DownloadSort) async -> [DownloadedTrackEntity] {
        let orderClause: String
        switch sort {
        case .recent:
            orderClause = "ORDER BY downloaded_at DESC"
        case .title:
            orderClause = "ORDER BY title COLLATE NOCASE ASC"
        case .artist:
            orderClause = "ORDER BY artist COLLATE NOCASE ASC, title COLLATE NOCASE ASC"
        }
        return (try? await DatabaseService.shared.fetchAll(
            DownloadedTrackEntity.self,
            sql: "SELECT * FROM downloaded_track \(orderClause)"
        )) ?? []
    }

    var activeDownloads: [(videoId: String, progress: Double)] {
        downloads.compactMap { videoId, state in
            if case .downloading(let progress) = state {
                return (videoId, progress)
            }
            return nil
        }
        .sorted { $0.progress > $1.progress }
    }

    func totalStorageBytes() -> Int64 {
        let keys = fileManager.enumerator(at: downloadsDir, includingPropertiesForKeys: [.fileSizeKey])?
            .compactMap { $0 as? URL } ?? []
        return keys.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    func deleteAll() async {
        cancelAllActiveDownloads()
        let tracks = await fetchAll()
        for track in tracks {
            try? fileManager.removeItem(atPath: track.localPath)
            _ = try? await DatabaseService.shared.delete(track)
        }
        downloads.removeAll()
        downloadedVideoIds.removeAll()
        persistedDownloadCount = 0
        cancelledDownloadIds.removeAll()
        lastReportedProgress.removeAll()
        objectWillChange.send()
    }

    func state(for videoId: String) -> DownloadState {
        if let state = downloads[videoId], state != .notStarted {
            return state
        }
        return downloadedVideoIds.contains(videoId) ? .completed : .notStarted
    }

    @discardableResult
    func ensureDirectories() -> Bool {
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        return true
    }

    private func ffmpegMetadataArgs(title: String, artist: String) -> [String] {
        ["-metadata", "title=\(title)", "-metadata", "artist=\(artist)"]
    }

    /// Uses ffmpeg to remux an existing AAC file with metadata (title/artist/artwork).
    /// `-c copy` avoids re-encoding — just copies the audio stream and injects metadata atoms.
    private func attachMetadata(to fileURL: URL, title: String, artist: String, artworkData: Data?) async throws {
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        var args = ["-y", "-i", fileURL.path, "-c", "copy"]
        args += ffmpegMetadataArgs(title: title, artist: artist)
        args.append(tempOutput.path)

        let session = FFmpegKit.execute(withArguments: args)
        let rc = session?.getReturnCode() ?? ReturnCode(1)
        try? fileManager.removeItem(at: fileURL)

        guard ReturnCode.isSuccess(rc) else {
            try? fileManager.removeItem(at: tempOutput)
            throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Metadata attach failed: \(session?.getOutput() ?? "")"])
        }
        try fileManager.moveItem(at: tempOutput, to: fileURL)
    }

    /// Transcodes a non-AAC stream (Opus, etc.) to AAC with metadata using ffmpeg.
    private func processAudio(
        inputURL: URL,
        outputURL: URL,
        title: String,
        artist: String,
        artworkData: Data?
    ) async throws -> URL {
        let bitrate = Self.transcodeBitrate(for: SettingsStore.shared.downloadQuality)
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        var args = ["-y", "-i", inputURL.path, "-c:a", "aac", "-b:a", "\(bitrate)"]
        args += ffmpegMetadataArgs(title: title, artist: artist)
        args.append(tempOutput.path)

        let session = FFmpegKit.execute(withArguments: args)
        let rc = session?.getReturnCode() ?? ReturnCode(1)

        guard ReturnCode.isSuccess(rc) else {
            try? fileManager.removeItem(at: tempOutput)
            throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio transcode failed: \(session?.getOutput() ?? "")"])
        }
        try? fileManager.removeItem(at: outputURL)
        try fileManager.moveItem(at: tempOutput, to: outputURL)
        return outputURL
    }

    private func sanitizedFileName(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return s.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

enum DownloadError: Error, LocalizedError {
    case invalidStreamURL
    case transcodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidStreamURL:
            return "The stream URL returned by the server was invalid"
        case .transcodeFailed:
            return "Could not convert this track for offline playback."
        }
    }
}
