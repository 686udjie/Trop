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
import AVFoundation

final class PlayerController {
    static let shared = PlayerController()

    private var mpv: OpaquePointer?
    private let playbackQueue = DispatchQueue(label: "com.686udjie.PlayerController")
    private var isRunning = false
    private var currentVideoId: String?
    private var pendingVideoId: String?

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

    private var nowPlayingInfo = [String: Any]()

    private init() {
        assertAudioSession()
        setupRemoteCommands()
        observeInterruptions()
        startMpv()
    }

    deinit {
        cleanup()
    }

    func stop() {
        guard let mpv = self.mpv else { return }
        _ = ["stop"].withUnsafeCArg { mpv_command(mpv, $0) }
        currentVideoId = nil
    }

    func play(url: String, title: String? = nil, artist: String? = nil, videoId: String? = nil, duration: TimeInterval? = nil, artists: [YTArtist] = []) async {
        guard let url = URL(string: url) else {
            print("[Player] Invalid URL: \(url)")
            return
        }

        if let videoId, let title, videoId != NowPlaying.shared.videoId {
            NowPlaying.shared.update(title: title, artist: artist, videoId: videoId, artists: artists)
        }

        let prevVideoId = currentVideoId
        currentVideoId = videoId
        if prevVideoId != nil, videoId != prevVideoId {
            await PlaybackStateService.shared.stopTracking()
        }
        if let videoId {
            await PlaybackStateService.shared.startTracking(videoId: videoId)
        }

        guard let mpv = self.mpv else {
            print("[Player] mpv not ready")
            return
        }

        pendingVideoId = videoId
        _ = ["loadfile", url.absoluteString, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
        NowPlaying.shared.isPlaying = true
        NowPlaying.shared.currentTime = 0
        if let duration, duration > 0 {
            NowPlaying.shared.duration = duration
        }
        setNowPlayingMetadata()
    }

    func cleanup() {
        isRunning = false
        if let mpv = self.mpv {
            mpv_wakeup(mpv)
        }
        if currentVideoId != nil {
            currentVideoId = nil
            Task { await PlaybackStateService.shared.stopTracking() }
        }
    }

    // MARK: - mpv lifecycle

    private func startMpv() {
        playbackQueue.async { [weak self] in
            guard let self else { return }

            guard let mpv = mpv_create() else {
                print("[Player] mpv_create failed")
                return
            }
            self.mpv = mpv

            mpv_set_option_string(mpv, "vo", "null")
            mpv_set_option_string(mpv, "keep-open", "no")
            mpv_set_option_string(mpv, "cache", "yes")
            mpv_set_option_string(mpv, "demuxer-max-bytes", "200M")
            mpv_set_option_string(mpv, "gapless-audio", "yes")
            mpv_request_log_messages(mpv, "info")

            if mpv_initialize(mpv) < 0 {
                print("[Player] mpv_initialize failed")
                mpv_destroy(mpv)
                self.mpv = nil
                return
            }

            mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)

            self.isRunning = true
            self.eventLoop(mpv)
        }
    }

    private func eventLoop(_ mpv: OpaquePointer) {
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
                var pauseFlag = Int32(1)
                mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
                let actuallyPlaying = pauseFlag == 0
                DispatchQueue.main.async {
                    self.playState.send(actuallyPlaying ? .playing : .paused)
                    NowPlaying.shared.isPlaying = actuallyPlaying
                    self.currentVideoId = self.pendingVideoId
                    self.assertAudioSession()
                    self.setNowPlayingMetadata()
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                if let prop = event.pointee.data?.load(as: mpv_event_property.self),
                   String(cString: prop.name) == "duration",
                   prop.format == MPV_FORMAT_DOUBLE,
                   let ptr = prop.data?.assumingMemoryBound(to: Double.self) {
                    let newDur = ptr.pointee
                    if newDur > 0 {
                        DispatchQueue.main.async {
                            NowPlaying.shared.duration = newDur
                            self.setNowPlayingMetadata()
                        }
                    }
                }
            case MPV_EVENT_START_FILE:
                break
            case MPV_EVENT_END_FILE:
                let stoppedVideoId = self.currentVideoId
                if stoppedVideoId != nil {
                    Task { await PlaybackStateService.shared.stopTracking() }
                }
                self.currentVideoId = nil
                let endFile = event.pointee.data?.load(as: mpv_event_end_file.self)
                let isEof = endFile?.reason == MPV_END_FILE_REASON_EOF
                DispatchQueue.main.async {
                    self.playState.send(.stopped)
                    NowPlaying.shared.stopped(videoId: stoppedVideoId, isEof: isEof)
                }
            default:
                break
            }
        }
        if let mpv = self.mpv {
            self.mpv = nil
            mpv_destroy(mpv)
        }
    }

    // MARK: - Audio Session

    func assertAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Player] Failed to assert audio session: \(error)")
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if playState.value == .playing {
                togglePlayPause()
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    assertAudioSession()
                    if playState.value == .paused {
                        togglePlayPause()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            if playState.value == .playing {
                togglePlayPause()
            }
        }
    }

    // MARK: - Now Playing Info

    func setNowPlayingMetadata() {
        assertAudioSession()
        let np = NowPlaying.shared

        var liveDur = Double(0)
        if let mpv { mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &liveDur) }
        let duration = liveDur > 0 ? liveDur : np.duration
        if duration > 0 { np.duration = duration }

        var livePos = Double(0)
        if let mpv { mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &livePos) }
        let elapsed = livePos > 0 ? livePos : np.currentTime

        nowPlayingInfo[MPMediaItemPropertyTitle] = np.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = np.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = np.albumTitle
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func updateNowPlayingArtwork() {
        let np = NowPlaying.shared
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func updateNowPlayingProgress() {
        guard let mpv else { return }
        let np = NowPlaying.shared

        var dur = Double(0)
        mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur)
        guard dur > 0 else { return }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
        info[MPMediaItemPropertyPlaybackDuration] = dur
        np.duration = dur

        var pos = Double(0)
        mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = pos
        np.currentTime = pos

        info[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            NowPlaying.shared.playNext()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            NowPlaying.shared.playPrevious()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            self?.updateNowPlayingProgress()
            return .success
        }
    }

    func seek(to time: TimeInterval) {
        guard let mpv = self.mpv else { return }
        var val = time
        let result = mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
        if result < 0 {
            print("[Player] seek failed: mpv error \(result)")
        }
    }

    func togglePlayPause() {
        guard let mpv = self.mpv else { return }
        let willBePlaying = playState.value == .paused || playState.value == .stopped
        var flag: Int32 = willBePlaying ? 0 : 1
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        playState.send(willBePlaying ? .playing : .paused)
        NowPlaying.shared.isPlaying = willBePlaying
        updateNowPlayingProgress()
    }
}

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
