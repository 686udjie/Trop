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
}

// Resolves an audio stream URL for a given client.
// PlaybackManager orchestrates the fallback chain; this is a single-client resolver.
enum StreamResolver {

    // Resolves the best audio stream URL for a given video with a specific client
    // - poToken: optional PoToken for web clients (playerRequestPoToken)
    // - streamingDataPoToken: optional PoToken appended to stream URL (&pot=)
    static func resolve(videoId: String, client: YouTubeClient,
                        poToken: String? = nil,
                        streamingDataPoToken: String? = nil) async throws -> PlaybackResult {
        print("[StreamResolver] Resolving videoId=\(videoId) client=\(client.clientName) v\(client.clientVersion)")

        // Fetch signature timestamp if the client requires it
        let signatureTimestamp: Int?
        if client.useSignatureTimestamp {
            signatureTimestamp = try? await PlayerJsFetcher.shared.getSignatureTimestamp()
            if signatureTimestamp != nil {
                print("[StreamResolver] Using signatureTimestamp=\(signatureTimestamp!)")
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
            print("[StreamResolver] ❌ Not playable: status=\(playabilityStatus.status ?? "?") reason=\(reason)")
            throw StreamError.unplayable(reason: reason)
        }

        print("[StreamResolver] ✅ Playable: status=OK")

        // Extract streaming data
        guard let streamingData = response.streamingData else {
            throw StreamError.noStreams
        }

        let adaptiveFormats = streamingData.adaptiveFormats ?? []
        print("[StreamResolver] Got \(adaptiveFormats.count) adaptive formats, expiresIn=\(streamingData.expiresInSeconds ?? "?")s")

        // Select best audio format
        guard let selectedFormat = FormatSelector.bestAudioFormat(from: adaptiveFormats) else {
            throw StreamError.noSuitableFormat
        }

        // Resolve the stream URL (direct or via cipher)
        let streamUrl: String
        if let url = selectedFormat.url, !url.isEmpty {
            streamUrl = url
            print("[StreamResolver] Direct URL: \(streamUrl.prefix(120))...")
        } else if let cipherText = selectedFormat.signatureCipher ?? selectedFormat.cipher {
            print("[StreamResolver] Format requires cipher deobfuscation")
            let playerJs = try await PlayerJsFetcher.shared.getPlayerJs()
            streamUrl = try await CipherExecutor.shared.resolveCipherURL(
                cipherText: cipherText,
                playerJs: playerJs,
                playerHash: nil
            )
            print("[StreamResolver] Resolved cipher URL: \(streamUrl.prefix(120))...")
        } else {
            throw StreamError.noStreamUrl
        }

        // Append &pot= for web client PoToken
        var finalStreamUrl = streamUrl
        if let pot = streamingDataPoToken, client.useWebPoTokens {
            finalStreamUrl += "&pot=" + pot.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            print("[StreamResolver] Appended &pot= to stream URL")
        }

        // Build result metadata
        let videoDetails = response.videoDetails
        let duration = videoDetails?.lengthSeconds.flatMap(Int.init)
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
            clientName: client.clientName
        )

        if let duration, let vid = videoDetails?.videoId {
            DurationCache.set(vid, duration)
        }

        print("[StreamResolver] Result: title=\"\(result.title ?? "?")\""
            + " author=\"\(result.author ?? "?")\""
            + " itag=\(result.itag)"
            + " quality=\(result.audioQuality)"
            + " bitrate=\(result.bitrate)")

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
            print("[StreamResolver] Invalid URL for validation")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[StreamResolver] HEAD validation: invalid response type")
                return false
            }
            let valid = (200...299).contains(httpResponse.statusCode)
            print("[StreamResolver] HEAD validation: status=\(httpResponse.statusCode) valid=\(valid)")
            return valid
        } catch {
            print("[StreamResolver] HEAD validation failed: \(error.localizedDescription)")
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
