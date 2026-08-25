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
    private lazy var downloadSession: URLSession = {
        URLSession(configuration: .default, delegate: downloadDelegate, delegateQueue: nil)
    }()
    private let downloadDelegate = DownloadSessionDelegate()
    private var downloadedVideoIds: Set<String> = []
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    private var cancelledDownloadIds: Set<String> = []
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
        currentPath?.usesInterfaceType(.wifi) == true
            || currentPath?.usesInterfaceType(.wiredEthernet) == true
    }

    /// AAC transcode bitrate for the download quality preference.
    static func transcodeBitrate(for quality: DownloadQuality) -> Int {
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
        let artist = song.artists.map(\.name).joined(separator: ", ")
        Log.downloadManager.debug("Starting download: \(artist) - \(song.title) (\(videoId))")
        setProgress(0.02, for: videoId)

        if SettingsStore.shared.wifiOnlyDownloads, !isOnWiFi {
            downloads[videoId] = .failed("Wi-Fi Only is enabled and you are not on Wi-Fi.")
            objectWillChange.send()
            return
        }

        do {
            let fileURL = downloadsDir.appendingPathComponent(
                sanitizedFileName("\(artist) - \(song.title).m4a")
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }

            async let artworkData = prefetchArtwork(from: song.thumbnailUrl)

            setProgress(0.05, for: videoId)
            let result = try await PlaybackManager.shared.resolve(
                videoId: videoId,
                forDownload: true
            )
            let streamURL = result.streamUrl
            let isAACStream = result.mimeType.lowercased().contains("mp4a")
                || result.mimeType.lowercased().contains("aac")
            Log.downloadManager.debug("Resolved stream: codec=\(result.mimeType) isAAC=\(isAACStream)")

            guard let url = URL(string: streamURL) else {
                throw DownloadError.invalidStreamURL
            }

            let tempDownload = fileManager.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(isAACStream ? "m4a" : "webm")")
            let expectedBytes = await expectedDownloadSize(for: videoId, result: result, song: song)
            try await downloadToFile(
                from: url,
                to: tempDownload,
                videoId: videoId,
                expectedBytes: expectedBytes
            )
            let artwork = await artworkData
            Log.downloadManager.debug("Fetched stream file for \(videoId)")

            ensureDirectories()
            setProgress(0.88, for: videoId)
            if isAACStream {
                Log.downloadManager.debug("AAC stream detected — saving directly (no transcode)")
                try fileManager.copyItem(at: tempDownload, to: fileURL)
                try await attachMetadata(
                    to: fileURL,
                    title: song.title,
                    artist: artist,
                    artworkData: artwork
                )
            } else {
                _ = try await processAudio(
                    inputURL: tempDownload,
                    outputURL: fileURL,
                    title: song.title,
                    artist: artist,
                    artworkData: artwork
                )
            }
            try? fileManager.removeItem(at: tempDownload)

            if cancelledDownloadIds.contains(videoId) {
                cancelledDownloadIds.remove(videoId)
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
            Log.downloadManager.debug("Completed download: \(artist) - \(song.title) -> \(fileURL.path)")
            objectWillChange.send()
        } catch {
            if cancelledDownloadIds.contains(videoId) || (error as? URLError)?.code == .cancelled {
                cancelledDownloadIds.remove(videoId)
                downloads[videoId] = .notStarted
                objectWillChange.send()
                return
            }
            downloads[videoId] = .failed(userFacingDownloadError(error))
            Log.downloadManager.error("Failed download \(videoId): \(error.localizedDescription)")
            objectWillChange.send()
        }
    }

    private func expectedDownloadSize(for videoId: String, result: PlaybackResult, song: SongItem) async -> Int64? {
        if let format = try? await DatabaseService.shared.fetchOne(FormatEntity.self, key: videoId),
           format.contentLength > 0 {
            return format.contentLength
        }
        if song.duration > 0, result.bitrate > 0 {
            return Int64(song.duration) * Int64(result.bitrate) / 8
        }
        return nil
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

    private func cancelActiveDownload(videoId: String) {
        cancelledDownloadIds.insert(videoId)
        activeDownloadTasks[videoId]?.cancel()
        activeDownloadTasks.removeValue(forKey: videoId)
    }

    private func cancelAllActiveDownloads() {
        for videoId in activeDownloadTasks.keys {
            cancelledDownloadIds.insert(videoId)
            activeDownloadTasks[videoId]?.cancel()
        }
        activeDownloadTasks.removeAll()
    }

    private func setProgress(_ fraction: Double, for videoId: String) {
        downloads[videoId] = .downloading(min(0.99, max(0, fraction)))
        objectWillChange.send()
    }

    private func prefetchArtwork(from thumbnailUrl: String?) async -> Data? {
        guard let thumbUrl = thumbnailUrl, let url = URL(string: thumbUrl) else { return nil }
        guard let image = try? await ImagePipeline.shared.image(for: url) else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    private func downloadToFile(
        from url: URL,
        to destination: URL,
        videoId: String,
        expectedBytes: Int64?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = downloadSession.downloadTask(with: url)
            activeDownloadTasks[videoId] = task
            downloadDelegate.register(
                task: task,
                destination: destination,
                expectedBytes: expectedBytes,
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.setProgress(0.10 + fraction * 0.75, for: videoId)
                    }
                },
                completion: { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
            task.resume()
        }
        activeDownloadTasks.removeValue(forKey: videoId)
    }

    func delete(videoId: String) async {
        cancelActiveDownload(videoId: videoId)
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
        let tracks = await fetchAll()
        switch sort {
        case .recent:
            return tracks.sorted { $0.downloadedAt > $1.downloadedAt }
        case .title:
            return tracks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .artist:
            return tracks.sorted {
                $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
            }
        }
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

    private func buildMetadata(title: String, artist: String, artworkData: Data?) -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []

        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        titleItem.extendedLanguageTag = "und"
        metadata.append(titleItem)

        let artistItem = AVMutableMetadataItem()
        artistItem.identifier = .commonIdentifierArtist
        artistItem.value = artist as NSString
        artistItem.extendedLanguageTag = "und"
        metadata.append(artistItem)

        if let imageData = artworkData {
            let artworkItem = AVMutableMetadataItem()
            artworkItem.identifier = .commonIdentifierArtwork
            artworkItem.value = imageData as NSData
            artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
            metadata.append(artworkItem)
        }

        return metadata
    }

    /// Re-muxes an existing AAC/M4A file through AVAssetReader/AVAssetWriter to
    /// embed title/artist/artwork metadata. `AVAssetWriter.metadata` reliably
    /// writes the `covr` atom the iOS Files app previewer reads; the audio is
    /// copied without re-encoding (passthrough), so this stays a fast path.
    private func attachMetadata(to fileURL: URL, title: String, artist: String, artworkData: Data?) async throws {
        let asset = AVURLAsset(url: fileURL)
        let metadata = buildMetadata(title: title, artist: artist, artworkData: artworkData)
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            // No decodable audio track: leave the file untouched.
            return
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: tempOutput, fileType: .m4a)
        writer.metadata = metadata

        // Passthrough requires a source format hint describing the audio format.
        let sourceFormat = try? await audioTrack.load(.formatDescriptions).first
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: sourceFormat
        )
        writer.add(writerInput)

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        try await transcode(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput)

        if writer.status == .completed {
            try? fileManager.removeItem(at: fileURL)
            try fileManager.moveItem(at: tempOutput, to: fileURL)
        } else {
            try? fileManager.removeItem(at: tempOutput)
            throw writer.error ?? NSError(
                domain: "DownloadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to attach metadata"]
            )
        }
    }

    private func processAudio(
        inputURL: URL,
        outputURL: URL,
        title: String,
        artist: String,
        artworkData: Data?
    ) async throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let tempOutput = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")

        let asset = AVURLAsset(url: inputURL)
        let metadata = buildMetadata(title: title, artist: artist, artworkData: artworkData)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw DownloadError.transcodeFailed
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: tempOutput, fileType: .m4a)
        writer.metadata = metadata

        let sourceFormat = try? await audioTrack.load(.formatDescriptions).first
        let sourceASBD = sourceFormat.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        let sampleRate = sourceASBD?.mSampleRate ?? 48000
        let channels = Int(sourceASBD?.mChannelsPerFrame ?? 2)

        // Passthrough when the source is already AAC (no re-encode needed);
        // otherwise transcode Opus/other → AAC.
        let isAAC = (sourceFormat?.mediaSubType.rawValue == kAudioFormatMPEG4AAC)
        let bitrate = Self.transcodeBitrate(for: SettingsStore.shared.downloadQuality)
        let audioSettings: [String: Any]? = isAAC ? nil : [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        writer.add(writerInput)

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        try await transcode(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput)

        if writer.status == .completed {
            try? fileManager.removeItem(at: outputURL)
            try fileManager.moveItem(at: tempOutput, to: outputURL)
            return outputURL
        } else {
            try? fileManager.removeItem(at: tempOutput)
            throw writer.error ?? NSError(
                domain: "DownloadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Audio transcode failed"]
            )
        }
    }

    /// Copies audio samples from `reader` into `writer` (optionally re-encoding
    /// via `writerInput`'s output settings) and finishes the writer. Shared by
    /// the metadata re-mux and the Opus→AAC transcode.
    private func transcode(
        reader: AVAssetReader,
        readerOutput: AVAssetReaderTrackOutput,
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput
    ) async throws {
        let session = TranscodeSession(
            reader: reader,
            readerOutput: readerOutput,
            writer: writer,
            writerInput: writerInput
        )
        try await withCheckedThrowingContinuation { continuation in
            session.run(continuation: continuation)
        }
    }

    /// Wraps the non-Sendable AVFoundation objects so they can be captured by the
    /// `@Sendable` `requestMediaDataWhenReady` callback without warnings.
    private struct TranscodeSession: @unchecked Sendable {
        let reader: AVAssetReader
        let readerOutput: AVAssetReaderTrackOutput
        let writer: AVAssetWriter
        let writerInput: AVAssetWriterInput

        func run(continuation: CheckedContinuation<Void, Error>) {
            var didFinish = false
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.trop.audio")) { [self] in
                guard !didFinish else { return }
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        didFinish = true
                        writerInput.markAsFinished()
                        if reader.status == .reading { reader.cancelReading() }
                        writer.finishWriting {
                            if let error = writer.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                }
            }
        }
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

// MARK: - Streaming download delegate

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Context {
        let destination: URL
        var stagingURL: URL?
        var expectedBytes: Int64?
        var onProgress: (@Sendable (Double) -> Void)?
        var completion: (@Sendable (Result<Void, Error>) -> Void)?
        var didFinish = false
    }

    private var contexts: [Int: Context] = [:]
    private let lock = NSLock()

    func register(
        task: URLSessionDownloadTask,
        destination: URL,
        expectedBytes: Int64?,
        onProgress: (@Sendable (Double) -> Void)?,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        lock.lock()
        contexts[task.taskIdentifier] = Context(
            destination: destination,
            stagingURL: nil,
            expectedBytes: expectedBytes,
            onProgress: onProgress,
            completion: completion,
            didFinish: false
        )
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let context = contexts[downloadTask.taskIdentifier]
        lock.unlock()
        guard let onProgress = context?.onProgress else { return }

        if totalBytesExpectedToWrite > 0 {
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            return
        }
        if let expected = context?.expectedBytes, expected > 0 {
            onProgress(min(1.0, Double(totalBytesWritten) / Double(expected)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        guard var context = contexts[downloadTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).download")
        do {
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try FileManager.default.copyItem(at: location, to: staging)
            context.stagingURL = staging
            contexts[downloadTask.taskIdentifier] = context
        } catch {
            context.didFinish = true
            contexts.removeValue(forKey: downloadTask.taskIdentifier)
            lock.unlock()
            context.completion?(.failure(error))
            return
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard var context = contexts.removeValue(forKey: task.taskIdentifier), !context.didFinish else {
            lock.unlock()
            return
        }
        context.didFinish = true
        let completion = context.completion
        lock.unlock()
        guard let completion else { return }

        if let error {
            if let staging = context.stagingURL {
                try? FileManager.default.removeItem(at: staging)
            }
            completion(.failure(error))
            return
        }

        guard let staging = context.stagingURL else {
            completion(.failure(DownloadError.invalidStreamURL))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: context.destination.path) {
                try FileManager.default.removeItem(at: context.destination)
            }
            try FileManager.default.moveItem(at: staging, to: context.destination)
            completion(.success(()))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            completion(.failure(error))
        }
    }
}
