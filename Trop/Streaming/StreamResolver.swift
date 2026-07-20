//
//  StreamResolver.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Result of a successful stream resolution
struct PlaybackResult {
    let streamUrl: String
    let itag: Int
    let mimeType: String
    let bitrate: Int
    let audioQuality: String
    let videoId: String
    let title: String?
    let author: String?
    let duration: Int?
    let expiresInSeconds: Int
    let clientName: String
    let musicVideoType: String?
    /// True if video dimensions exist, serving as a reliable signal for clients omitting musicVideoType
    let hasVideoContent: Bool
    /// Provides a combined audio-video stream URL to enable instant toggling by swapping the `vid` track, avoiding reloads and network fetches
    let muxedStreamUrl: String?
}

// Resolves an audio stream URL for a given client.
// PlaybackManager orchestrates the fallback chain; this is a single-client resolver.
enum StreamResolver {

    // Resolves the best audio stream URL for a given video with a specific client
    // - poToken: optional PoToken for web clients (playerRequestPoToken)
    // - streamingDataPoToken: optional PoToken appended to stream URL (&pot=)
    static func resolve(videoId: String, client: YouTubeClient,
                        poToken: String? = nil,
                        streamingDataPoToken: String? = nil,
                        preferredFormat: Format? = nil,
                        forDownload: Bool = false) async throws -> PlaybackResult {
        Log.streamResolver.debug("Resolving videoId=\(videoId) client=\(client.clientName) v\(client.clientVersion)")

        // Fetch signature timestamp if the client requires it
        let signatureTimestamp: Int?
        if client.useSignatureTimestamp {
            signatureTimestamp = try? await PlayerJsFetcher.shared.getSignatureTimestamp()
            if let ts = signatureTimestamp {
                Log.streamResolver.debug("Using signatureTimestamp=\(ts)")
            }
        } else {
            signatureTimestamp = nil
        }

        let response = try await InnerTube.shared.playerResponse(
            videoId: videoId,
            client: client,
            signatureTimestamp: signatureTimestamp,
            poToken: poToken
        )

        // Validate playability
        guard let playabilityStatus = response.playabilityStatus else {
            throw StreamError.unplayable(reason: "No playability status in response")
        }

        guard playabilityStatus.status == "OK" else {
            let reason = playabilityStatus.reason ?? "Unknown"
            Log.streamResolver.error("❌ Not playable: status=\(playabilityStatus.status ?? "?") reason=\(reason)")
            throw StreamError.unplayable(reason: reason)
        }

        Log.streamResolver.debug("✅ Playable: status=OK")

        // Extract streaming data
        guard let streamingData = response.streamingData else {
            throw StreamError.noStreams
        }

        let adaptiveFormats = streamingData.adaptiveFormats ?? []
        Log.streamResolver.debug("Got \(adaptiveFormats.count) adaptive formats, expiresIn=\(streamingData.expiresInSeconds ?? "?")s")

        let allFormats = (streamingData.formats ?? []) + adaptiveFormats
        let maxVideoHeight = allFormats.compactMap { $0.height }.max() ?? 0
        let hasVideoContent = maxVideoHeight >= 480
        Log.streamResolver.debug("hasVideoContent=\(hasVideoContent) (maxVideoHeight=\(maxVideoHeight), video formats: \(allFormats.filter { $0.width != nil }.count))")

        // Select best audio format. For downloads, prefer an AAC/MP4 streams
        let selectedFormat: Format
        if let preferred = preferredFormat, adaptiveFormats.contains(where: { $0.itag == preferred.itag }) {
            selectedFormat = preferred
            Log.streamResolver.debug("Using preferred format itag=\(preferred.itag ?? 0)")
        } else if forDownload, let downloadFormat = FormatSelector.bestDownloadFormat(from: allFormats) {
            selectedFormat = downloadFormat
        } else if let best = FormatSelector.bestAudioFormat(from: allFormats) {
            selectedFormat = best
        } else {
            let formatInfos = allFormats.map { f in
                "itag=\(f.itag ?? 0) mime=\(f.mimeType ?? "?") audio=\(f.audioChannels != nil) url=\(f.url != nil) cipher=\(f.signatureCipher != nil || f.cipher != nil)"
            }
            Log.streamResolver.error("No suitable format. Formats: \(formatInfos.joined(separator: ", "))")
            throw StreamError.noSuitableFormat
        }

        // Resolve the stream URL (direct or via cipher)
        let streamUrl: String
        if let url = selectedFormat.url, !url.isEmpty {
            streamUrl = url
            Log.streamResolver.debug("Direct URL: \(streamUrl.prefix(120))...")
        } else if let cipherText = selectedFormat.signatureCipher ?? selectedFormat.cipher {
            Log.streamResolver.debug("Format requires cipher deobfuscation")
            let playerJs = try await PlayerJsFetcher.shared.getPlayerJs()
            streamUrl = try await CipherExecutor.shared.resolveCipherURL(
                cipherText: cipherText,
                playerJs: playerJs,
                playerHash: nil
            )
            Log.streamResolver.debug("Resolved cipher URL: \(streamUrl.prefix(120))...")
        } else {
            throw StreamError.noStreamUrl
        }

        // Append &pot= for web client PoToken
        var finalStreamUrl = streamUrl
        if let pot = streamingDataPoToken, client.useWebPoTokens {
            finalStreamUrl += "&pot=" + pot.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            Log.streamResolver.debug("Appended &pot= to stream URL")
        }

        // Build result metadata
        let videoDetails = response.videoDetails
        let duration = videoDetails?.lengthSeconds.flatMap(Int.init)
        let musicVideoType = videoDetails?.musicVideoType

        let muxedStreamUrl: String? = {
            guard let videoFormat = FormatSelector.bestVideoFormat(from: allFormats),
                  let url = videoFormat.url, !url.isEmpty else {
                return nil
            }
            var muxed = url
            if let pot = streamingDataPoToken, client.useWebPoTokens {
                muxed += "&pot=" + pot.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            }
            return muxed
        }()

        let result = PlaybackResult(
            streamUrl: finalStreamUrl,
            itag: selectedFormat.itag ?? 0,
            mimeType: selectedFormat.mimeType ?? "",
            bitrate: selectedFormat.bitrate ?? 0,
            audioQuality: selectedFormat.audioQuality ?? "",
            videoId: videoDetails?.videoId ?? videoId,
            title: videoDetails?.title,
            author: videoDetails?.author,
            duration: duration,
            expiresInSeconds: streamingData.expiresInSeconds.flatMap(Int.init) ?? 0,
            clientName: client.clientName,
            musicVideoType: musicVideoType,
            hasVideoContent: hasVideoContent,
            muxedStreamUrl: muxedStreamUrl
        )
        Log.streamResolver.debug("musicVideoType=\(musicVideoType ?? "nil")")

        if let duration, let vid = videoDetails?.videoId {
            DurationCache.set(vid, duration)
        }

        Log.streamResolver.debug("Result: title=\"\(result.title ?? "?")\" author=\"\(result.author ?? "?")\" itag=\(result.itag) quality=\(result.audioQuality) bitrate=\(result.bitrate)")

        // Cache format info for playback tracking
        let trackingUrl = response.playbackTracking?.videostatsPlaybackUrl?.baseUrl
        let contentLength = (selectedFormat.contentLength as NSString?)?.longLongValue ?? 0
        let formatEntity = FormatEntity(
            id: videoId,
            itag: selectedFormat.itag ?? 0,
            mimeType: selectedFormat.mimeType ?? "",
            codecs: selectedFormat.codec,
            bitrate: selectedFormat.bitrate ?? 0,
            sampleRate: 0,
            contentLength: contentLength,
            loudnessDb: selectedFormat.loudnessDb,
            perceptualLoudnessDb: nil,
            playbackUrl: trackingUrl
        )
        _ = try? await DatabaseService.shared.insertOrReplace(formatEntity)

        return result
    }

    // Validates a stream URL by sending a HEAD request
    static func validateStream(url: String) async -> Bool {
        guard let url = URL(string: url) else {
            Log.streamResolver.error("Invalid URL for validation")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Log.streamResolver.error("HEAD validation: invalid response type")
                return false
            }
            let valid = (200...299).contains(httpResponse.statusCode)
            Log.streamResolver.debug("HEAD validation: status=\(httpResponse.statusCode) valid=\(valid)")
            return valid
        } catch {
            Log.streamResolver.error("HEAD validation failed: \(error.localizedDescription)")
            return false
        }
    }
}

// Errors that can occur during stream resolution
enum StreamError: Error, LocalizedError {
    case unplayable(reason: String)
    case noStreams
    case noSuitableFormat
    case noStreamUrl
    case validationFailed(String)
    case allClientsFailed

    var errorDescription: String? {
        switch self {
        case .unplayable(let reason):
            return "Not playable: \(reason)"
        case .noStreams:
            return "No streaming data in response"
        case .noSuitableFormat:
            return "No suitable audio format found"
        case .noStreamUrl:
            return "Format has no direct stream URL and no cipher data"
        case .validationFailed(let client):
            return "\(client) stream URL failed HEAD validation"
        case .allClientsFailed:
            return "All clients failed to resolve a valid stream URL"
        }
    }
}
