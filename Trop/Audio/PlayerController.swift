//
//  PlayerController.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation
import Libmpv
import MediaPlayer
import Combine

// Simple player using mpv C API
final class PlayerController {
    static let shared = PlayerController()

    private var mpv: OpaquePointer?
    private var playbackQueue = DispatchQueue(label: "com.686udjie.PlayerController")
    private var isRunning = false
    private var currentVideoId: String?

    // State for UI
    let playState = CurrentValueSubject<State, Never>(.stopped)

    var currentTime: TimeInterval {
        guard let mpv else { return 0 }
        var val = Double(0)
        mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
        return val
    }

    var duration: TimeInterval {
        guard let mpv else { return 0 }
        var val = Double(0)
        mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &val)
        return val
    }

    enum State: Equatable {
        case stopped, playing, paused
    }

    private init() {}

    deinit {
        cleanup()
    }

    // Start playback of a stream URL
    func play(url: String, title: String? = nil, artist: String? = nil, videoId: String? = nil) {
        guard let url = URL(string: url) else {
            print("[Player] Invalid URL: \(url)")
            return
        }
        print("[Player] Playing: \(url.lastPathComponent)")

        if let videoId, let title {
            NowPlaying.shared.update(title: title, artist: artist, videoId: videoId)
        }

        if isRunning { stopTracking() }

        currentVideoId = videoId
        if let videoId {
            Task { await PlaybackStateService.shared.startTracking(videoId: videoId) }
        }

        playbackQueue.async { [weak self] in
            guard let self else { return }
            self.destroyMpv()

            guard let mpv = mpv_create() else {
                print("[Player] mpv_create failed")
                return
            }
            self.mpv = mpv

            mpv_set_option_string(mpv, "vo", "null")
            mpv_set_option_string(mpv, "keep-open", "no")
            mpv_set_option_string(mpv, "cache", "yes")
            mpv_set_option_string(mpv, "demuxer-max-bytes", "200M")
            mpv_request_log_messages(mpv, "info")

            if mpv_initialize(mpv) < 0 {
                print("[Player] mpv_initialize failed")
                mpv_destroy(mpv)
                self.mpv = nil
                return
            }

            let ret = ["loadfile", url.absoluteString, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
            print("[Player] loadfile returned \(ret)")

            DispatchQueue.main.async {
                self.playState.send(.playing)
            }

            self.eventLoop(mpv)
        }
    }

    // Cleanup (kills mpv and ends event loop)
    func cleanup() {
        stopTracking()
        isRunning = false
        destroyMpv()
    }

    private func stopTracking() {
        let videoId = currentVideoId
        currentVideoId = nil
        if videoId != nil {
            Task { await PlaybackStateService.shared.stopTracking() }
        }
    }

    private func destroyMpv() {
        guard let mpv = self.mpv else { return }
        mpv_destroy(mpv)
        self.mpv = nil
    }

    private func eventLoop(_ mpv: OpaquePointer) {
        isRunning = true
        while isRunning {
            guard let event = mpv_wait_event(mpv, 0.2) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                break
            case MPV_EVENT_LOG_MESSAGE:
                if let prop = event.pointee.data?.load(as: mpv_event_log_message.self) {
                    let text = String(cString: prop.text)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("[mpv] \(text)", terminator: "")
                    }
                }
            case MPV_EVENT_FILE_LOADED:
                print("[Player] File loaded")
            case MPV_EVENT_START_FILE:
                print("[Player] Start file")
            case MPV_EVENT_END_FILE:
                print("[Player] End file")
                isRunning = false
                self.stopTracking()
                self.destroyMpv()
                DispatchQueue.main.async {
                    self.playState.send(.stopped)
                    NowPlaying.shared.stopped()
                }
                return
            default:
                break
            }
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            if self?.mpv != nil {
                let url = URL(fileURLWithPath: "mainplaylist://mainplaylist").absoluteString
                self?.play(url: url)
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // Seek helper
    func seek(to time: TimeInterval) {
        playbackQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            var val = time
            mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
        }
    }

    func togglePlayPause() {
        let willBePlaying = playState.value == .paused || playState.value == .stopped
        playState.send(willBePlaying ? .playing : .paused)
        NowPlaying.shared.isPlaying = willBePlaying

        playbackQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            var flag: Int = willBePlaying ? 0 : 1
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        }
    }
}

// Helper for passing C strings to mpv_command
extension Array where Element == String {
    func withUnsafeCArg<T>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> T) -> T {
        let cstrings = map { strdup($0) }
        defer { cstrings.forEach { free($0) } }
        var ptrs = cstrings.map { UnsafePointer($0) } + [nil]
        return ptrs.withUnsafeMutableBufferPointer { buf in
            body(buf.baseAddress)
        }
    }
}
