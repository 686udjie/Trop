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
import Nuke
import UIKit

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [String: DownloadState] = [:]

    enum DownloadState: Equatable {
        case notStarted
        case downloading(Double)
        case completed
        case failed(String)
    }

    private let fileManager = FileManager.default
    private var downloadsDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Trop/Downloads")
    }

    private init() {}

    func download(song: SongItem) async {
        let videoId = song.videoId
        let artist = song.artists.map(\.name).joined(separator: ", ")
        print("[DownloadManager] Starting download: \(artist) - \(song.title) (\(videoId))")
        downloads[videoId] = .downloading(0)

        do {
            let fileURL = downloadsDir.appendingPathComponent(
                sanitizedFileName("\(artist) - \(song.title).m4a")
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }

            // Prefer an AAC/MP4 stream so the bytes can be saved directly
            // without a slow Opus→AAC re-encode (Metrolist-style fast path).
            let result = try await PlaybackManager.shared.resolve(
                videoId: videoId,
                forDownload: true
            )
            let streamURL = result.streamUrl
            let isAACStream = result.mimeType.lowercased().contains("mp4a")
                || result.mimeType.lowercased().contains("aac")
            print("[DownloadManager] Resolved stream: codec=\(result.mimeType) isAAC=\(isAACStream)")

            // Stream the response in chunks (avoids per-byte copies and
            // per-byte @Published notifications, which were the main slowdown).
            let (bytes, response) = try await URLSession.shared.bytes(from: URL(string: streamURL)!)
            let expected = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
            var data = Data()
            if expected > 0 { data.reserveCapacity(Int(expected)) }
            var received: Int64 = 0
            var chunk = Data()
            chunk.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                chunk.append(byte)
                received += 1
                if chunk.count >= 64 * 1024 {
                    data.append(chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if expected > 0 {
                        downloads[videoId] = .downloading(0.2 + 0.4 * (Double(received) / Double(expected)))
                    }
                }
            }
            if !chunk.isEmpty { data.append(chunk) }
            print("[DownloadManager] Fetched \(data.count) bytes for \(videoId)")

            ensureDirectories()
            if isAACStream {
                // Fast path: write AAC bytes directly, then re-mux to attach metadata.
                print("[DownloadManager] AAC stream detected — saving directly (no transcode)")
                try data.write(to: fileURL)
                try await attachMetadata(to: fileURL, title: song.title, artist: artist, thumbnailUrl: song.thumbnailUrl)
            } else {
                _ = try await processAudio(
                    data: data,
                    outputURL: fileURL,
                    title: song.title,
                    artist: artist,
                    thumbnailUrl: song.thumbnailUrl
                )
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

            downloads[videoId] = .completed
            print("[DownloadManager] Completed download: \(artist) - \(song.title) -> \(fileURL.path)")
            objectWillChange.send()
        } catch {
            downloads[videoId] = .failed(error.localizedDescription)
            print("[DownloadManager] Failed download \(videoId): \(error.localizedDescription)")
            objectWillChange.send()
        }
    }

    func delete(videoId: String) async {
        downloads[videoId] = .notStarted
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
        localURL(for: videoId) != nil
    }

    func fetchAll() async -> [DownloadedTrackEntity] {
        (try? await DatabaseService.shared.fetchAll(DownloadedTrackEntity.self)) ?? []
    }

    @discardableResult
    func ensureDirectories() -> Bool {
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        return true
    }

    private func buildMetadata(title: String, artist: String, thumbnailUrl: String?) async -> [AVMetadataItem] {
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

        if let thumbUrl = thumbnailUrl, let url = URL(string: thumbUrl) {
            if let image = try? await ImagePipeline.shared.image(for: url),
               let imageData = image.jpegData(compressionQuality: 0.9) {
                let artworkItem = AVMutableMetadataItem()
                artworkItem.identifier = .commonIdentifierArtwork
                artworkItem.value = imageData as NSData
                artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
                metadata.append(artworkItem)
            }
        }

        return metadata
    }

    /// Re-muxes an existing AAC/M4A file through AVAssetReader/AVAssetWriter to
    /// embed title/artist/artwork metadata. `AVAssetWriter.metadata` reliably
    /// writes the `covr` atom the iOS Files app previewer reads; the audio is
    /// copied without re-encoding (passthrough), so this stays a fast path.
    private func attachMetadata(to fileURL: URL, title: String, artist: String, thumbnailUrl: String?) async throws {
        let asset = AVURLAsset(url: fileURL)
        let metadata = await buildMetadata(title: title, artist: artist, thumbnailUrl: thumbnailUrl)
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
        data: Data,
        outputURL: URL,
        title: String,
        artist: String,
        thumbnailUrl: String?
    ) async throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let tempInput = tempDir.appendingPathComponent("\(UUID().uuidString).webm")
        let tempOutput = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")
        try data.write(to: tempInput)

        let asset = AVURLAsset(url: tempInput)
        let metadata = await buildMetadata(title: title, artist: artist, thumbnailUrl: thumbnailUrl)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            // No decodable audio track: keep raw data but with a neutral extension
            try data.write(to: tempOutput)
            try? fileManager.removeItem(at: tempInput)
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.moveItem(at: tempOutput, to: outputURL)
            return outputURL
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
        let audioSettings: [String: Any]? = isAAC ? nil : [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 192000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        writer.add(writerInput)

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        try await transcode(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput)

        try? fileManager.removeItem(at: tempInput)

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
