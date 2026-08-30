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
import SwiftUI
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
    private var activeFFmpegSessions: [String: FFmpegSession] = [:]
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
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reconcileDownloadedFiles()
            }
        }
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
}

// MARK: - Download

extension DownloadManager {
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

            let artwork = await artworkData

            ensureDirectories()
            setProgress(0.88, for: videoId)
            let ffmpegStart = CFAbsoluteTimeGetCurrent()
            if isAACStream {
                // AVFoundation can open AAC/MP4; validate before remux.
                let validateStart = CFAbsoluteTimeGetCurrent()
                try await validateDownloadedFile(at: tempDownload)
                Log.downloadManager.debug("VALIDATE \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - validateStart))s")

                Log.downloadManager.debug("FFMPEG remux (AAC passthrough)...")
                try await attachMetadata(
                    to: tempDownload,
                    title: song.title,
                    artist: artist,
                    artworkData: artwork,
                    videoId: videoId
                )
                try fileManager.moveItem(at: tempDownload, to: fileURL)
            } else {
                // WebM/Opus is not readable by AVFoundation — transcode first,
                // then validate the generated .m4a.
                Log.downloadManager.debug("FFMPEG transcode (Opus -> AAC)...")
                try await processAudio(
                    TranscodeRequest(
                        inputURL: tempDownload,
                        outputURL: fileURL,
                        title: song.title,
                        artist: artist,
                        artworkData: artwork
                    ),
                    videoId: videoId
                )
                let validateStart = CFAbsoluteTimeGetCurrent()
                do {
                    try await validateDownloadedFile(at: fileURL)
                } catch {
                    try? fileManager.removeItem(at: fileURL)
                    throw error
                }
                Log.downloadManager.debug("VALIDATE \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - validateStart))s")
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
        } catch is CancellationError {
            cancelledDownloadIds.remove(videoId)
            lastReportedProgress.removeValue(forKey: videoId)
            downloads[videoId] = .notStarted
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
}

    // MARK: - Validation & Errors

extension DownloadManager {
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

    // MARK: - Refresh & State

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
        for (videoId, state) in downloads {
            if case .downloading = state {
                cancelledDownloadIds.insert(videoId)
            }
        }
        for (videoId, session) in activeFFmpegSessions {
            cancelledDownloadIds.insert(videoId)
            session.cancel()
        }
        activeFFmpegSessions.removeAll()
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

    // MARK: - File Transfer (ffmpeg)

    private func downloadToFile(
        from url: URL,
        to destination: URL,
        videoId: String
    ) async throws {
        guard let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") else {
            throw NSError(
                domain: "DownloadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "CA certificate bundle not found"]
            )
        }

        let args = [
            "-y",
            "-rw_timeout", "30000000",
            "-cafile", caPath,
            "-headers", "User-Agent: Mozilla/5.0\r\n",
            "-i", url.absoluteString,
            "-c", "copy",
            destination.path
        ]

        try await runFFmpeg(arguments: args, videoId: videoId) { [weak self] size in
            Task { @MainActor in
                // Asymptotic map so unknown Content-Length still moves the bar.
                let fraction = 0.05 + 0.80 * (1 - exp(-Double(size) / 5_000_000))
                self?.setProgress(fraction, for: videoId)
            }
        }
    }

    /// Runs FFmpeg off the main actor via the async API; optionally reports size stats.
    private func runFFmpeg(
        arguments: [String],
        videoId: String? = nil,
        onSize: ((Int64) -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var finished = false
            let finish: (Result<Void, Error>) -> Void = { result in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }

            let session = FFmpegKit.execute(
                withArgumentsAsync: arguments,
                withCompleteCallback: { [weak self] session in
                    if let videoId {
                        Task { @MainActor in
                            self?.activeFFmpegSessions.removeValue(forKey: videoId)
                        }
                    }
                    let rc = session?.getReturnCode()
                    if ReturnCode.isSuccess(rc) {
                        finish(.success(()))
                    } else if ReturnCode.isCancel(rc) {
                        finish(.failure(CancellationError()))
                    } else {
                        let output = session?.getOutput() ?? "unknown"
                        Log.downloadManager.debug("FFmpeg output: \(output)")
                        finish(.failure(NSError(
                            domain: "DownloadManager",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "FFmpeg processing failed"]
                        )))
                    }
                },
                withLogCallback: nil,
                withStatisticsCallback: { statistics in
                    guard let statistics, let onSize else { return }
                    onSize(Int64(statistics.getSize()))
                }
            )

            if let videoId, let session {
                Task { @MainActor in
                    self.activeFFmpegSessions[videoId] = session
                }
            }
        }
    }

    // MARK: - Delete

    func delete(videoId: String) async {
        cancelledDownloadIds.insert(videoId)
        if let session = activeFFmpegSessions.removeValue(forKey: videoId) {
            session.cancel()
        }
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

    // MARK: - Local URL Resolution

    func localURL(for videoId: String) async -> URL? {
        guard let entity = try? await DatabaseService.shared.read({ db in
            try DownloadedTrackEntity.fetchOne(db, key: videoId)
        }) else {
            Log.downloadManager.debug("localURL: no DB entity for \(videoId)")
            return nil
        }

        let storedURL = URL(fileURLWithPath: entity.localPath)
        if fileManager.fileExists(atPath: storedURL.path) {
            return storedURL
        }

        let currentURL = downloadsDir.appendingPathComponent(
            sanitizedFileName("\(entity.artist) - \(entity.title).m4a")
        )
        if fileManager.fileExists(atPath: currentURL.path) {
            Log.downloadManager.debug("localURL: \(videoId) resolved via current downloadsDir")
            try? await DatabaseService.shared.write { db in
                var updated = entity
                updated.localPath = currentURL.path
                try updated.update(db)
            }
            return currentURL
        }

        Log.downloadManager.debug("localURL: \(videoId) file not found (stored=\(entity.localPath), current=\(currentURL.path))")
        return nil
    }

    // MARK: - Query Helpers

    func isDownloaded(videoId: String) -> Bool {
        downloadedVideoIds.contains(videoId)
    }

    func reconcileDownloadedFiles() async {
        let allTracks = await fetchAll()
        var validIds = Set<String>()
        for track in allTracks {
            if await localURL(for: track.id) != nil {
                validIds.insert(track.id)
            } else {
                _ = try? await DatabaseService.shared.delete(track)
            }
        }
        if validIds != downloadedVideoIds {
            downloadedVideoIds = validIds
            persistedDownloadCount = validIds.count
            objectWillChange.send()
        }
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

    func totalStorageBytes() async -> Int64 {
        let tracks = (try? await DatabaseService.shared.fetchAll(DownloadedTrackEntity.self)) ?? []
        var total: Int64 = 0
        for track in tracks {
            guard let url = await localURL(for: track.id) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
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
        // Keep cancelledDownloadIds so in-flight download(song:) ops still see cancel.
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

    private func writeTempArtwork(_ data: Data?) throws -> URL? {
        guard let data else { return nil }
        let url = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    /// Uses ffmpeg to remux an existing AAC file with metadata (title/artist/artwork).
    /// `-c copy` avoids re-encoding — just copies the audio stream and injects metadata atoms.
    private func attachMetadata(
        to fileURL: URL,
        title: String,
        artist: String,
        artworkData: Data?,
        videoId: String
    ) async throws {
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let artworkURL = try writeTempArtwork(artworkData)
        defer {
            try? fileManager.removeItem(at: tempOutput)
            if let artworkURL {
                try? fileManager.removeItem(at: artworkURL)
            }
        }

        var args = ["-y", "-i", fileURL.path]
        if let artworkURL {
            args += [
                "-i", artworkURL.path,
                "-map", "0:a",
                "-map", "1",
                "-c:a", "copy",
                "-c:v", "mjpeg",
                "-disposition:v", "attached_pic"
            ]
        } else {
            args += ["-c", "copy"]
        }
        args += ffmpegMetadataArgs(title: title, artist: artist)
        args.append(tempOutput.path)

        try await runFFmpeg(arguments: args, videoId: videoId)
        try? fileManager.removeItem(at: fileURL)
        try fileManager.moveItem(at: tempOutput, to: fileURL)
    }

    /// Transcodes a non-AAC stream (Opus, etc.) to AAC with metadata using ffmpeg.
    private func processAudio(_ request: TranscodeRequest, videoId: String) async throws {
        let bitrate = Self.transcodeBitrate(for: SettingsStore.shared.downloadQuality)
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let artworkURL = try writeTempArtwork(request.artworkData)
        defer {
            try? fileManager.removeItem(at: tempOutput)
            if let artworkURL {
                try? fileManager.removeItem(at: artworkURL)
            }
        }

        var args = ["-y", "-i", request.inputURL.path]
        if let artworkURL {
            args += [
                "-i", artworkURL.path,
                "-map", "0:a",
                "-map", "1",
                "-c:a", "aac",
                "-b:a", "\(bitrate)",
                "-c:v", "mjpeg",
                "-disposition:v", "attached_pic"
            ]
        } else {
            args += ["-c:a", "aac", "-b:a", "\(bitrate)"]
        }
        args += ffmpegMetadataArgs(title: request.title, artist: request.artist)
        args.append(tempOutput.path)

        try await runFFmpeg(arguments: args, videoId: videoId)
        try? fileManager.removeItem(at: request.outputURL)
        try fileManager.moveItem(at: tempOutput, to: request.outputURL)
    }

    private struct TranscodeRequest {
        let inputURL: URL
        let outputURL: URL
        let title: String
        let artist: String
        let artworkData: Data?
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

// MARK: - Environment

private struct DownloadManagerEnvironmentKey: EnvironmentKey {
    @MainActor static var defaultValue: DownloadManager { .shared }
}

extension EnvironmentValues {
    var downloadManager: DownloadManager {
        get { self[DownloadManagerEnvironmentKey.self] }
        set { self[DownloadManagerEnvironmentKey.self] = newValue }
    }
}
