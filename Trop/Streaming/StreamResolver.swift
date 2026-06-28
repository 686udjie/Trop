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
    let expiresInSeconds: Int
    let clientName: String
}

// Resolves audio stream URLs via YouTube's /player endpoint
// Uses direct-URL clients (ANDROID_VR) that don't need cipher deobfuscation
enum StreamResolver {

    // Resolves the best audio stream URL for a given video
    // Returns both the stream URL and metadata about the selected format
    static func resolve(videoId: String, client: YouTubeClient = .androidVr1_43_32) async throws -> PlaybackResult {
        print("[StreamResolver] Resolving videoId=\(videoId) client=\(client.clientName) v\(client.clientVersion)")

        let response = try await InnerTube.shared.playerResponse(videoId: videoId, client: client)

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

        // Get the direct stream URL (ANDROID_VR clients populate format.url)
        guard let streamUrl = selectedFormat.url, !streamUrl.isEmpty else {
            print("[StreamResolver] Format has no direct URL — would need cipher deobfuscation")
            if selectedFormat.signatureCipher != nil || selectedFormat.cipher != nil {
                throw StreamError.needsCipher
            }
            throw StreamError.noStreamUrl
        }

        print("[StreamResolver] ✅ Stream URL: \(streamUrl.prefix(120))...")

        // Build result metadata
        let videoDetails = response.videoDetails
        let result = PlaybackResult(
            streamUrl: streamUrl,
            itag: selectedFormat.itag ?? 0,
            mimeType: selectedFormat.mimeType ?? "",
            bitrate: selectedFormat.bitrate ?? 0,
            audioQuality: selectedFormat.audioQuality ?? "",
            videoId: videoDetails?.videoId ?? videoId,
            title: videoDetails?.title,
            author: videoDetails?.author,
            expiresInSeconds: streamingData.expiresInSeconds.flatMap(Int.init) ?? 0,
            clientName: client.clientName
        )

        print("[StreamResolver] Result: title=\"\(result.title ?? "?")\""
            + " author=\"\(result.author ?? "?")\""
            + " itag=\(result.itag)"
            + " quality=\(result.audioQuality)"
            + " bitrate=\(result.bitrate)")

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
    case needsCipher

    var errorDescription: String? {
        switch self {
        case .unplayable(let reason):
            return "Not playable: \(reason)"
        case .noStreams:
            return "No streaming data in response"
        case .noSuitableFormat:
            return "No suitable audio format found"
        case .noStreamUrl:
            return "Format has no direct stream URL"
        case .needsCipher:
            return "Stream requires cipher deobfuscation (Milestone 4)"
        }
    }
}
