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
import UIKit
import Metal

// MARK: - DetectedCrop (parsed from mpv log)

struct DetectedCrop {
    let width: Int
    let height: Int
    let x: Int
    let y: Int
}

// MARK: - PlayerController

final class PlayerController {
    static let shared = PlayerController()

    var mpv: OpaquePointer?
    let playbackQueue = DispatchQueue(label: "com.686udjie.PlayerController")
    var isRunning = false
    var currentVideoId: String?
    var pendingVideoId: String?
    private var lastDetectedCrop: String?
    private var detectedCropRepeatCount = 0
    var currentLoudnessDb: Double?
    var pendingURL: String?

    // Video-mode state (main-actor).
    var videoModeSwitchInFlight = false
    var loadedMuxedURL: String?
    var muxedActive = false
    var muxedVideoId: String?
    var hasPresentedVideo = false

    var videoLayer: CAMetalLayer = {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.contentsScale = 1
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 180)
        layer.frame = bounds
        layer.drawableSize = CGSize(
            width: bounds.width * layer.contentsScale,
            height: bounds.height * layer.contentsScale
        )
        return layer
    }()

    let playState = CurrentValueSubject<State, Never>(.stopped)
    var pendingResumeAt: TimeInterval = 0
    var nowPlayingInfo = [String: Any]()

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

    enum State: Equatable { case stopped, playing, paused }

    private init() {
        assertAudioSession()
        setupRemoteCommands()
        observeInterruptions()
        startMpv()
    }

    deinit { cleanup() }

    func cleanup() {
        isRunning = false
        if let mpv = self.mpv { mpv_wakeup(mpv) }
        if currentVideoId != nil {
            currentVideoId = nil
            Task { await PlaybackStateService.shared.stopTracking() }
        }
    }

    // MARK: - Layer helper

    func clearVideoLayer() {
        guard let device = videoLayer.device,
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let drawable = videoLayer.nextDrawable() else { return }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    @MainActor
    func applyPendingResumeIfNeeded() {
        guard pendingResumeAt > 0 else { return }
        let target = pendingResumeAt
        pendingResumeAt = 0
        seek(to: target)
    }
}

// MARK: - Playback

extension PlayerController {
    @MainActor
    func play(
        url: String,
        title: String? = nil,
        artist: String? = nil,
        videoId: String? = nil,
        duration: TimeInterval? = nil,
        artists: [YTArtist] = [],
        loudnessDb: Double? = nil
    ) async {
        currentLoudnessDb = loudnessDb
        guard let url = URL(string: url) else {
            Log.player.error("Invalid URL: \(url)")
            return
        }

        if let videoId, let title, videoId != NowPlaying.shared.videoId {
            NowPlaying.shared.update(title: title, artist: artist, videoId: videoId, artists: artists)
        }

        let prevVideoId = currentVideoId
        let isNewSong = prevVideoId != nil && videoId != prevVideoId
        currentVideoId = videoId

        if isNewSong {
            await PlaybackStateService.shared.stopTracking()
        }
        loadedMuxedURL = nil
        muxedActive = false
        muxedVideoId = nil
        pendingResumeAt = 0
        videoModeSwitchInFlight = false
        NowPlaying.shared.isVideoMode = false
        if hasPresentedVideo { clearVideoLayer() }
        if let videoId { await PlaybackStateService.shared.startTracking(videoId: videoId) }

        guard let mpv = self.mpv else {
            Log.player.info("mpv not ready yet, parking URL for deferred load")
            pendingURL = url.absoluteString
            pendingVideoId = videoId
            return
        }

        applyPlaybackSettings()
        setVideoCrop(.none)

        pendingVideoId = videoId
        Log.player.info(
            "TRANSITION play videoId=\(videoId ?? "nil") isNewSong=\(isNewSong) muxedActive=\(muxedActive) url=\(url.absoluteString.prefix(80))"
        )
        let cmdResult = ["loadfile", url.absoluteString, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
        Log.player.info("mpv_command loadfile result=\(cmdResult)")
        NowPlaying.shared.isPlaying = true
        NowPlaying.shared.currentTime = 0
        if let duration, duration > 0 { NowPlaying.shared.duration = duration }
        setNowPlayingMetadata()
    }

    @MainActor
    func seek(to time: TimeInterval) {
        guard let mpv = self.mpv else { return }
        var val = time
        let result = mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
        if result < 0 { Log.player.error("seek failed: mpv error \(result)") }
    }

    @MainActor
    func setPaused(_ paused: Bool) {
        guard let mpv = self.mpv else { return }
        let currentlyPaused = playState.value != .playing
        guard currentlyPaused != paused else {
            updateNowPlayingProgress()
            return
        }
        var flag: Int32 = paused ? 1 : 0
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        playState.send(paused ? .paused : .playing)
        NowPlaying.shared.isPlaying = !paused
        if !paused { assertAudioSession() }
        updateNowPlayingProgress()
    }

    @MainActor
    func togglePlayPause() {
        setPaused(playState.value == .playing)
    }

    func setPlayerVolume(_ volume: Double) {
        SettingsStore.shared.playerVolume = min(1, max(0, volume))
        applyPlayerVolume()
    }

    func applyPlayerVolume() {
        guard let mpv else { return }
        var val = Double(SettingsStore.shared.playerVolume * 100)
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &val)
    }

    func applyPlaybackSettings() {
        guard let mpv else { return }
        let settings = SettingsStore.shared
        mpv_set_property_string(mpv, "gapless-audio", settings.gaplessPlayback ? "yes" : "no")

        var filters: [String] = []

        if settings.equalizerEnabled {
            let entries = zip(equalizerFrequencies, settings.equalizerGains)
                .map { "entry(\(Self.fmt($0.0)),\(Self.fmt($0.1)))" }
                .joined(separator: ";")
            if !entries.isEmpty {
                filters.append("firequalizer=gain_entry=\"\(entries)\"")
            }
        }

        if settings.audioNormalization, let loudness = currentLoudnessDb, loudness.isFinite {
            let gain = max(-12, min(12, -14 - loudness))
            filters.append("volume=\(Self.fmt(gain))dB")
        }

        let chain = filters.joined(separator: ",")
        let result = mpv_set_property_string(mpv, "af", chain.isEmpty ? "" : chain)
        if result < 0 { Log.player.error("Failed to set af chain '\(chain)': mpv error \(result)") }
        applyPlayerVolume()
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

// MARK: - mpv lifecycle & event loop

extension PlayerController {
    fileprivate func startMpv() {
        playbackQueue.async { [weak self] in
            guard let self else { return }
            guard let mpv = mpv_create() else {
                Log.player.error("mpv_create failed")
                return
            }

            mpv_request_log_messages(mpv, "warn")
            applyMpvStartupOptions(mpv)

            Log.player.info("mpv initializing...")
            let initResult = mpv_initialize(mpv)
            guard initResult >= 0 else {
                let errStr = String(cString: mpv_error_string(initResult))
                Log.player.error("mpv_initialize failed: \(initResult) (\(errStr))")
                mpv_destroy(mpv)
                self.mpv = nil
                return
            }
            Log.player.info("mpv initialized successfully")

            applyPostInitProperties(mpv)
            applyObservedProperties(mpv)

            self.mpv = mpv
            Log.player.info("mpv handle published — event loop starting")

            self.applyPlaybackSettings()

            if let url = self.pendingURL {
                self.pendingURL = nil
                Log.player.info("mpv ready: loading deferred URL \(url.prefix(80))")
                _ = ["loadfile", url, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
            }

            self.isRunning = true
            self.eventLoop(mpv)
        }
    }

    private func applyMpvStartupOptions(_ mpv: OpaquePointer) {
        mpv_set_option_string(mpv, "vo", "null")
        mpv_set_option_string(mpv, "vid", "no")
        mpv_set_option_string(mpv, "force-window", "no")

        #if targetEnvironment(simulator)
        mpv_set_option_string(mpv, "hwdec", "no")
        mpv_set_option_string(mpv, "audio-exclusive", "no")
        #else
        mpv_set_option_string(mpv, "hwdec", "videotoolbox")
        mpv_set_option_string(mpv, "audio-exclusive", "yes")
        #endif

        mpv_set_option_string(mpv, "keep-open", "no")
        mpv_set_option_string(mpv, "cache", "yes")
        mpv_set_option_string(mpv, "cache-secs", "120")
        mpv_set_option_string(mpv, "demuxer-max-bytes", "200M")
        mpv_set_option_string(mpv, "gapless-audio", "yes")
    }

    private func applyPostInitProperties(_ mpv: OpaquePointer) {
        if let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
            mpv_set_property_string(mpv, "tls-ca-file", caPath)
            Log.player.info("mpv tls-ca-file set: \(caPath)")
        } else {
            Log.player.warning("mpv cacert.pem not found in main bundle")
        }
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" +
            " (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        mpv_set_property_string(mpv, "user-agent", userAgent)
        mpv_set_property_string(mpv, "background", "0x00000000")
        mpv_set_property_string(mpv, "video-unscaled", "no")
        mpv_set_property_string(mpv, "keepaspect", "no")
    }

    private func applyObservedProperties(_ mpv: OpaquePointer) {
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 1, "video-params/w", MPV_FORMAT_INT64)
    }

    fileprivate func eventLoop(_ mpv: OpaquePointer) {
        while isRunning {
            guard let event = mpv_wait_event(mpv, 0.2) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                break
            case MPV_EVENT_LOG_MESSAGE:
                handleLogMessage(event)
            case MPV_EVENT_FILE_LOADED:
                handleFileLoaded(mpv, event)
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event)
            case MPV_EVENT_START_FILE:
                Log.player.debug("TRANSITION START_FILE")
            case MPV_EVENT_END_FILE:
                handleEndFile(event)
            default:
                break
            }
        }
        if let mpv = self.mpv {
            self.mpv = nil
            mpv_destroy(mpv)
        }
    }

    private func handleLogMessage(_ event: UnsafeMutablePointer<mpv_event>) {
        if let prop = event.pointee.data?.load(as: mpv_event_log_message.self),
           let textPtr = prop.text {
            let text = String(cString: textPtr)
            let prefix = prop.prefix.map { String(cString: $0) } ?? ""
            let level = prop.level.map { String(cString: $0) } ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Log.mpv.debug("[\(prefix)] [\(level)] \(trimmed)")
                if let crop = detectedCrop(from: trimmed) {
                    DispatchQueue.main.async { self.applyDetectedCrop(crop) }
                }
            }
        }
    }

    private func handleFileLoaded(_ mpv: OpaquePointer, _ event: UnsafeMutablePointer<mpv_event>) {
        var pauseFlag = Int32(1)
        mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
        let actuallyPlaying = pauseFlag == 0
        Log.player.debug("TRANSITION FILE_LOADED videoId=\(pendingVideoId ?? "nil") playing=\(actuallyPlaying)")
        let aoPtr = mpv_get_property_string(mpv, "current-ao")
        let aoName = aoPtr.map { String(cString: $0) } ?? "nil"
        if let aoPtr { mpv_free(aoPtr) }
        Log.player.info("MPV_AO current-ao=\(aoName)")
        DispatchQueue.main.async {
            self.playState.send(actuallyPlaying ? .playing : .paused)
            NowPlaying.shared.isPlaying = actuallyPlaying
            self.currentVideoId = self.pendingVideoId
            self.assertAudioSession()
            self.setNowPlayingMetadata()
            self.applyPendingResumeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard self?.currentVideoId == self?.pendingVideoId else { return }
                self?.updateNowPlayingArtwork()
                self?.updateNowPlayingProgress()
            }
        }
    }

    private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let prop = event.pointee.data?.load(as: mpv_event_property.self),
              let namePtr = prop.name else { return }
        let name = String(cString: namePtr)
        if name == "duration",
           prop.format == MPV_FORMAT_DOUBLE,
           let ptr = prop.data?.assumingMemoryBound(to: Double.self) {
            let newDur = ptr.pointee
            if newDur > 0 {
                DispatchQueue.main.async {
                    NowPlaying.shared.duration = newDur
                    self.setNowPlayingMetadata()
                }
            }
        } else if name == "video-params/w", prop.format == MPV_FORMAT_INT64 {
            let width = prop.data?.assumingMemoryBound(to: Int64.self)
            if let width, width.pointee > 0 {
                Log.player.debug("TRANSITION video-params/w=\(width.pointee) videoId=\(currentVideoId ?? "nil")")
                DispatchQueue.main.async {
                    let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
                    guard ok else { return }
                    if self.hasPresentedVideo { self.clearVideoLayer() }
                    NowPlaying.shared.isVideoMode = true
                    self.hasPresentedVideo = true
                }
            }
        }
    }

    private func handleEndFile(_ event: UnsafeMutablePointer<mpv_event>) {
        let stoppedVideoId = currentVideoId
        let endFile = event.pointee.data?.load(as: mpv_event_end_file.self)
        let reason = endFile?.reason ?? MPV_END_FILE_REASON_EOF
        let errCode = endFile?.error ?? 0
        let errStr = mpv_error_string(errCode).map { String(cString: $0) } ?? "unknown"
        let isEof = reason == MPV_END_FILE_REASON_EOF
        let isFailure = reason == MPV_END_FILE_REASON_ERROR
        Log.player.debug(
            "TRANSITION END_FILE reason=\(reason) error=\(errCode)" +
            "(\(errStr)) isEof=\(isEof) isFailure=\(isFailure) stoppedVideoId=\(stoppedVideoId ?? "nil")"
        )
        if isEof || isFailure, stoppedVideoId != nil {
            Task { await PlaybackStateService.shared.stopTracking() }
        }
        currentVideoId = nil
        if isEof || isFailure {
            DispatchQueue.main.async {
                self.playState.send(.stopped)
                NowPlaying.shared.stopped(videoId: stoppedVideoId, isEof: isEof)
            }
        }
    }
}

// MARK: - Video mode

extension PlayerController {
    @MainActor
    func setVideoMode() {
        guard let videoId = NowPlaying.shared.videoId else { return }
        if muxedActive {
            NowPlaying.shared.isVideoMode = true
            return
        }
        guard !videoModeSwitchInFlight else { return }
        videoModeSwitchInFlight = true
        Task {
            defer { videoModeSwitchInFlight = false }
            do {
                let resumeAt = currentTime
                let url: String
                if let loaded = loadedMuxedURL {
                    url = loaded
                } else {
                    url = try await PlaybackManager.shared.resolveMuxedURL(videoId: videoId)
                    guard NowPlaying.shared.videoId == videoId else { return }
                    loadedMuxedURL = url
                }
                guard NowPlaying.shared.videoId == videoId else { return }
                setVideoTrack()
                Log.player.debug("TRANSITION entering video mode videoId=\(videoId) url=\(url.prefix(80))")
                muxedVideoId = videoId
                loadFileReplacing(url, startAt: resumeAt)
                muxedActive = true
            } catch {
                Log.player.error("setVideoMode failed: \(error)")
                NowPlaying.shared.isVideoMode = false
            }
        }
    }

    @MainActor
    func preloadVideoURL() {
        guard loadedMuxedURL == nil else { return }
        guard let videoId = NowPlaying.shared.videoId else { return }
        Task {
            do {
                let url = try await PlaybackManager.shared.resolveMuxedURL(videoId: videoId)
                guard NowPlaying.shared.videoId == videoId, loadedMuxedURL == nil else { return }
                loadedMuxedURL = url
            } catch {
                Log.player.error("Video preload failed: \(error)")
            }
        }
    }

    @MainActor
    func handleVideoStreamFailure() {
        guard muxedActive || videoModeSwitchInFlight else { return }
        loadedMuxedURL = nil
        muxedActive = false
        muxedVideoId = nil
        videoModeSwitchInFlight = false
        NowPlaying.shared.isVideoMode = false
    }

    private func setVideoTrack() {
        guard let mpv else { return }
        lastDetectedCrop = nil
        detectedCropRepeatCount = 0
        mpv_set_property_string(mpv, "vo", "gpu-next")
        mpv_set_property_string(mpv, "gpu-api", "vulkan")
        mpv_set_property_string(mpv, "gpu-context", "moltenvk")
        var wid = unsafeBitCast(videoLayer, to: Int64.self)
        mpv_set_property(mpv, "wid", MPV_FORMAT_INT64, &wid)
        mpv_set_property_string(mpv, "vid", "auto")
        setVideoCrop(.none)
    }

    private func detectedCrop(from log: String) -> DetectedCrop? {
        guard let marker = log.range(of: "crop=") else { return nil }
        let values = log[marker.upperBound...]
            .split(whereSeparator: { $0 == Character(":") || $0 == Character(" ") || $0 == Character("\n") })
            .prefix(4)
            .compactMap { Int($0) }
        guard values.count == 4 else { return nil }
        return DetectedCrop(width: values[0], height: values[1], x: values[2], y: values[3])
    }

    @MainActor
    private func applyDetectedCrop(_ crop: DetectedCrop) {
        guard crop.width > 0, crop.height > 0 else { return }
        let signature = "\(crop.width)x\(crop.height)+\(crop.x)+\(crop.y)"
        if lastDetectedCrop == signature {
            detectedCropRepeatCount += 1
        } else {
            lastDetectedCrop = signature
            detectedCropRepeatCount = 1
        }
        guard detectedCropRepeatCount >= 2 else { return }
        mpv_set_property_string(mpv, "video-crop", signature)
    }

    enum VideoCropMode { case none, square }

    private func setVideoCrop(_ mode: VideoCropMode) {
        guard let mpv else { return }
        switch mode {
        case .none:
            mpv_set_property_string(mpv, "video-crop", "")
        case .square:
            var w = Int64(0), h = Int64(0)
            mpv_get_property(mpv, "video-params/w", MPV_FORMAT_INT64, &w)
            mpv_get_property(mpv, "video-params/h", MPV_FORMAT_INT64, &h)
            if w > 0, h > 0 {
                let side = min(w, h)
                mpv_set_property_string(mpv, "video-crop", "\(side)x\(side)")
            } else {
                var vid: UnsafeMutablePointer<CChar>?
                defer { if let vid { mpv_free(vid) } }
                if mpv_get_property(mpv, "vid", MPV_FORMAT_STRING, &vid) == 0,
                   let vid, String(cString: vid) != "no" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.setVideoCrop(.square)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadFileReplacing(_ url: String, startAt: TimeInterval = 0) {
        guard let mpv else { return }
        pendingResumeAt = startAt
        Log.player.debug("TRANSITION loadFileReplacing startAt=\(startAt) url=\(url.prefix(80))")
        let args = ["loadfile", url, "replace"]
        _ = args.withUnsafeCArg { mpv_command(mpv, $0) }
    }
}

// MARK: - Audio session / interruption handling

extension PlayerController {
    func assertAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
            Log.player.info(
                "AUDIO_SESSION category=\(session.category.rawValue) active=\(session.isOtherAudioPlaying ? "yes(otherPlaying)" : "yes") " +
                "outputs=\(session.currentRoute.outputs.map(\.portName).joined(separator: ","))"
            )
        } catch {
            Log.player.error("Failed to assert audio session: \(error)")
        }
    }

    private func logBackgroundSnapshot(_ phase: String) {
        let session = AVAudioSession.sharedInstance()
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        Log.player.info(
            "BG_SNAPSHOT[\(phase)] state=\(playState.value) " +
            "title=\(nowPlayingInfo[MPMediaItemPropertyTitle] ?? "-") " +
            "infoKeys=\(info?.keys.count ?? 0) rate=\(info?[MPNowPlayingInfoPropertyPlaybackRate] ?? "-") " +
            "category=\(session.category.rawValue)"
        )
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

        Log.player.info("AUDIO_INTERRUPTION began")
        switch type {
        case .began:
            if playState.value == .playing { Task { @MainActor in togglePlayPause() } }
        case .ended:
            Log.player.info("AUDIO_INTERRUPTION ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    assertAudioSession()
                    if playState.value == .paused { Task { @MainActor in togglePlayPause() } }
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

        Log.player.info("ROUTE_CHANGE reason=\(reason.rawValue)")
        if reason == .oldDeviceUnavailable, playState.value == .playing {
            Task { @MainActor in togglePlayPause() }
        }
    }
}

// MARK: - Now Playing info / lock-screen

extension PlayerController {
    @MainActor
    func setNowPlayingMetadata() {
        assertAudioSession()
        let np = NowPlaying.shared
        nowPlayingInfo.removeAll()

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
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1 : 0
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        if duration > 0 { nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        Log.player.info(
            "NOW_PLAYING_PUBLISH title='\(np.title)' artist='\(np.artist)' " +
            "duration=\(duration) rate=\(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] ?? 0) " +
            "artwork=\(np.thumbnailUIImage != nil) keys=\(nowPlayingInfo.keys.count)"
        )
    }

    @MainActor
    func updateNowPlayingArtwork() {
        let np = NowPlaying.shared
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    @MainActor
    func updateNowPlayingProgress() {
        guard let mpv else { return }
        let np = NowPlaying.shared

        var dur = Double(0)
        mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur)
        guard dur > 0 else { return }

        var info = nowPlayingInfo
        info[MPMediaItemPropertyPlaybackDuration] = dur
        np.duration = dur

        var pos = Double(0)
        mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = pos
        np.currentTime = pos

        info[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1 : 0
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if UIApplication.shared.applicationState != .active,
           Date().timeIntervalSince(Self.lastBackgroundHeartbeat) > 2 {
            Self.lastBackgroundHeartbeat = Date()
            Log.player.info(
                "BG_HEARTBEAT appState=\(UIApplication.shared.applicationState.rawValue) " +
                "playing=\(np.isPlaying) pos=\(pos) keys=\(info.keys.count)"
            )
        }
    }

    private static var lastBackgroundHeartbeat = Date.distantPast
}

// MARK: - Remote commands

extension PlayerController {
    static func registerRemoteControlSupport() {
        DispatchQueue.main.async {
            UIApplication.shared.beginReceivingRemoteControlEvents()
            Log.player.info("REMOTE_COMMANDS launch-time beginReceivingRemoteControlEvents")
        }
    }

    fileprivate func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND play fired")
            Task { @MainActor [weak self] in self?.setPaused(false) }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND pause fired")
            Task { @MainActor [weak self] in self?.setPaused(true) }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND togglePlayPause fired")
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            Log.player.info("REMOTE_COMMAND next fired")
            Task { @MainActor in NowPlaying.shared.playNext() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            Log.player.info("REMOTE_COMMAND previous fired")
            Task { @MainActor in NowPlaying.shared.playPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Log.player.info("REMOTE_COMMAND seek fired to=\(position)")
            Task { @MainActor [weak self] in
                self?.seek(to: position)
                self?.updateNowPlayingProgress()
            }
            return .success
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.logBackgroundSnapshot("resignActive") }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.logBackgroundSnapshot("enterBackground")
            for delaySeconds in [0.6, 3] as [Double] {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    guard let self, UIApplication.shared.applicationState != .active else { return }
                    self.setNowPlayingMetadata()
                    self.updateNowPlayingProgress()
                    Log.player.info("BG_REPUBLISH after=\(delaySeconds)s")
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.logBackgroundSnapshot("becomeActive") }
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
