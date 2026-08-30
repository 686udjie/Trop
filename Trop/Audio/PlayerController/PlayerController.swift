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

@MainActor
final class PlayerController {
    static let shared = PlayerController()

    nonisolated(unsafe) private var _mpv: OpaquePointer?
    /// Serial queue for all mpv property read/write calls
    let mpvAccessQueue = DispatchQueue(label: "com.686udjie.PlayerController.mpvAccess")

    nonisolated(unsafe) private var eventLoopThread: Thread?

    nonisolated(unsafe) var isRunning = false
    nonisolated(unsafe) var currentVideoId: String?
    nonisolated(unsafe) var pendingVideoId: String?
    private var lastDetectedCrop: String?
    private var detectedCropRepeatCount = 0
    var currentLoudnessDb: Double?
    var pendingURL: String?

    /// Video-mode state. Reads happen on the event loop thread from event handlers;
    /// writes happen on the main actor from `setVideoMode` / `loadFileReplacing`.
    /// Cross-thread access is serialized by the event loop reading these values
    /// synchronously before dispatching work to the main actor.
    nonisolated(unsafe) var videoModeSwitchInFlight = false
    nonisolated(unsafe) var loadedMuxedURL: String?
    nonisolated(unsafe) var muxedActive = false
    nonisolated(unsafe) var muxedVideoId: String?
    nonisolated(unsafe) var hasPresentedVideo = false

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
        withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
    }

    var duration: TimeInterval {
        withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
    }

    enum State: Equatable { case stopped, playing, paused }

    private init() {
        assertAudioSession()
        setupRemoteCommands()
        observeInterruptions()
        startMpv()
    }

    deinit {
        isRunning = false
        if let mpv = _mpv { mpv_wakeup(mpv) }
    }

    nonisolated func withMpv<T: Sendable>(_ body: @escaping @Sendable (OpaquePointer) -> T) -> T? {
        var result: T?
        mpvAccessQueue.sync {
            guard let handle = _mpv else { return }
            result = body(handle)
        }
        return result
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

        let isReady = withMpv { _ in true } ?? false
        guard isReady else {
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
        let absoluteString = url.absoluteString
        let cmdResult = withMpv { mpv in
            ["loadfile", absoluteString, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
        } ?? -1
        Log.player.info("mpv_command loadfile result=\(cmdResult)")
        NowPlaying.shared.isPlaying = true
        NowPlaying.shared.currentTime = 0
        if let duration, duration > 0 { NowPlaying.shared.duration = duration }
        setNowPlayingMetadata()
    }

    func seek(to time: TimeInterval) {
        withMpv { mpv in
            var val = time
            let result = mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
            if result < 0 { Log.player.error("seek failed: mpv error \(result)") }
        }
    }

    func setPaused(_ paused: Bool) {
        let currentlyPaused = playState.value != .playing
        guard currentlyPaused != paused else {
            updateNowPlayingProgress()
            return
        }
        withMpv { mpv in
            var flag: Int32 = paused ? 1 : 0
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        }
        playState.send(paused ? .paused : .playing)
        NowPlaying.shared.isPlaying = !paused
        if !paused { assertAudioSession() }
        updateNowPlayingProgress()
    }

    func togglePlayPause() {
        setPaused(playState.value == .playing)
    }

    func setPlayerVolume(_ volume: Double) {
        SettingsStore.shared.playerVolume = min(1, max(0, volume))
        applyPlayerVolume()
    }

    func applyPlayerVolume() {
        let vol = SettingsStore.shared.playerVolume
        withMpv { mpv in
            var val = Double(vol * 100)
            mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &val)
        }
    }

    func applyPlaybackSettings() {
        let settings = SettingsStore.shared
        let loudness = currentLoudnessDb
        let eqEnabled = settings.equalizerEnabled
        let eqGains = settings.equalizerGains
        let gapless = settings.gaplessPlayback
        let norm = settings.audioNormalization

        let chain: String = {
            var filters: [String] = []
            if eqEnabled {
                let entries = zip(equalizerFrequencies, eqGains)
                    .map { "entry(\(Self.fmt($0.0)),\(Self.fmt($0.1)))" }
                    .joined(separator: ";")
                if !entries.isEmpty {
                    filters.append("firequalizer=gain_entry=\"\(entries)\"")
                }
            }
            if norm, let loudness, loudness.isFinite {
                let gain = max(-12, min(12, -14 - loudness))
                filters.append("volume=\(Self.fmt(gain))dB")
            }
            return filters.joined(separator: ",")
        }()

        withMpv { mpv in
            mpv_set_property_string(mpv, "gapless-audio", gapless ? "yes" : "no")
            let result = mpv_set_property_string(mpv, "af", chain.isEmpty ? "" : chain)
            if result < 0 { Log.player.error("Failed to set af chain '\(chain)': mpv error \(result)") }
        }
        applyPlayerVolume()
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

// MARK: - mpv lifecycle & event loop

extension PlayerController {
    fileprivate func startMpv() {
        mpvAccessQueue.async { [weak self] in
            guard let self else { return }
            guard let mpv = mpv_create() else {
                Log.player.error("mpv_create failed")
                return
            }

            mpv_request_log_messages(mpv, "warn")
            Self.applyMpvStartupOptions(mpv)

            Log.player.info("mpv initializing...")
            let initResult = mpv_initialize(mpv)
            guard initResult >= 0 else {
                let errStr = String(cString: mpv_error_string(initResult))
                Log.player.error("mpv_initialize failed: \(initResult) (\(errStr))")
                mpv_destroy(mpv)
                return
            }
            Log.player.info("mpv initialized successfully")

            Self.applyPostInitProperties(mpv)
            Self.applyObservedProperties(mpv)

            self._mpv = mpv
            Log.player.info("mpv handle published — event loop starting")

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyPlaybackSettings()
                if let url = self.pendingURL {
                    self.pendingURL = nil
                    Log.player.info("mpv ready: loading deferred URL \(url.prefix(80))")
                    _ = self.withMpv { mpv in
                        ["loadfile", url, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
                    }
                }
            }

            let thread = Thread { [weak self] in
                guard let self else { return }
                self.isRunning = true
                self.eventLoop(mpv)
            }
            self.eventLoopThread = thread
            thread.name = "com.686udjie.PlayerController.eventLoop"
            thread.start()
        }
    }

    nonisolated private static func applyMpvStartupOptions(_ mpv: OpaquePointer) {
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

    nonisolated private static func applyPostInitProperties(_ mpv: OpaquePointer) {
        if let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
            mpv_set_property_string(mpv, "tls-ca-file", caPath)
            Log.player.info("mpv tls-ca-file set: \(caPath)")
        } else {
            Log.player.warning("mpv cacert.pem not found in main bundle")
        }
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" +
            " (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        mpv_set_property_string(mpv, "user-agent", userAgent)
        mpv_set_property_string(mpv, "video-unscaled", "no")
        mpv_set_property_string(mpv, "keepaspect", "no")
    }

    nonisolated private static func applyObservedProperties(_ mpv: OpaquePointer) {
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 1, "video-params/w", MPV_FORMAT_INT64)
    }

    nonisolated fileprivate func eventLoop(_ mpv: OpaquePointer) {
        while isRunning {
            guard let event = mpv_wait_event(mpv, 0.2) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                break
            case MPV_EVENT_LOG_MESSAGE:
                handleLogMessage(event)
            case MPV_EVENT_FILE_LOADED:
                handleFileLoaded(mpv)
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event)
            case MPV_EVENT_START_FILE:
                Log.player.debug("TRANSITION START_FILE")
            case MPV_EVENT_END_FILE:
                handleEndFile()
            default:
                break
            }
        }
        _mpv = nil
        mpv_destroy(mpv)
    }

    nonisolated private func handleLogMessage(_ event: UnsafeMutablePointer<mpv_event>) {
        if let prop = event.pointee.data?.load(as: mpv_event_log_message.self),
           let textPtr = prop.text {
            let text = String(cString: textPtr)
            let prefix = prop.prefix.map { String(cString: $0) } ?? ""
            let level = prop.level.map { String(cString: $0) } ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Log.mpv.debug("[\(prefix)] [\(level)] \(trimmed)")
                if let crop = detectedCrop(from: trimmed) {
                    Task { @MainActor in self.applyDetectedCrop(crop) }
                }
            }
        }
    }

    nonisolated private func handleFileLoaded(_ mpv: OpaquePointer) {
        var pauseFlag = Int32(1)
        mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
        let actuallyPlaying = pauseFlag == 0
        let aoPtr = mpv_get_property_string(mpv, "current-ao")
        let aoName = aoPtr.map { String(cString: $0) } ?? "nil"
        if let aoPtr { mpv_free(aoPtr) }
        let pendingVideoId = self.pendingVideoId
        Task { @MainActor [weak self] in
            guard let self else { return }
            Log.player.debug("TRANSITION FILE_LOADED videoId=\(pendingVideoId ?? "nil") playing=\(actuallyPlaying)")
            Log.player.info("MPV_AO current-ao=\(aoName)")
            self.playState.send(actuallyPlaying ? .playing : .paused)
            NowPlaying.shared.isPlaying = actuallyPlaying
            self.currentVideoId = pendingVideoId
            self.assertAudioSession()
            self.setNowPlayingMetadata()
            self.applyPendingResumeIfNeeded()
            let checkId = self.pendingVideoId
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.currentVideoId == checkId else { return }
                self.updateNowPlayingArtwork()
                self.updateNowPlayingProgress()
            }
        }
    }

    nonisolated private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let prop = event.pointee.data?.load(as: mpv_event_property.self),
              let namePtr = prop.name else { return }
        let name = String(cString: namePtr)

        if name == "duration", prop.format == MPV_FORMAT_DOUBLE {
            let newDur: Double = prop.data?.load(as: Double.self) ?? 0
            if newDur > 0 {
                Task { @MainActor in
                    NowPlaying.shared.duration = newDur
                    self.setNowPlayingMetadata()
                }
            }
        } else if name == "video-params/w", prop.format == MPV_FORMAT_INT64 {
            let width: Int64 = prop.data?.load(as: Int64.self) ?? 0
            if width > 0 {
                Log.player.debug("TRANSITION video-params/w=\(width) videoId=\(self.currentVideoId ?? "nil")")
                Task { @MainActor in
                    let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
                    guard ok else { return }
                    if self.hasPresentedVideo { self.clearVideoLayer() }
                    NowPlaying.shared.isVideoMode = true
                    self.hasPresentedVideo = true
                }
            }
        }
    }

    nonisolated private func handleEndFile() {
        let stoppedVideoId = self.currentVideoId
        Task { @MainActor [weak self] in
            guard let self else { return }
            let videoId = stoppedVideoId
            let isEof = self.playState.value != .stopped && self.currentVideoId == nil
            let isFailure = false
            Log.player.debug(
                "TRANSITION END_FILE isEof=\(isEof) isFailure=\(isFailure) stoppedVideoId=\(videoId ?? "nil")"
            )
            if isEof || isFailure, videoId != nil {
                Task { await PlaybackStateService.shared.stopTracking() }
            }
            self.currentVideoId = nil
            if isEof || isFailure {
                self.playState.send(.stopped)
                NowPlaying.shared.stopped(videoId: videoId, isEof: isEof)
            }
        }
    }
}

// MARK: - Video mode

extension PlayerController {
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

    func handleVideoStreamFailure() {
        guard muxedActive || videoModeSwitchInFlight else { return }
        loadedMuxedURL = nil
        muxedActive = false
        muxedVideoId = nil
        videoModeSwitchInFlight = false
        NowPlaying.shared.isVideoMode = false
    }

    private func setVideoTrack() {
        lastDetectedCrop = nil
        detectedCropRepeatCount = 0
        let wid: Int64 = unsafeBitCast(videoLayer, to: Int64.self)
        withMpv { mpv in
            mpv_set_property_string(mpv, "vo", "gpu-next")
            mpv_set_property_string(mpv, "gpu-api", "vulkan")
            mpv_set_property_string(mpv, "gpu-context", "moltenvk")
            var widCopy = wid
            mpv_set_property(mpv, "wid", MPV_FORMAT_INT64, &widCopy)
            mpv_set_property_string(mpv, "vid", "auto")
        }
        setVideoCrop(.none)
    }

    nonisolated private func detectedCrop(from log: String) -> DetectedCrop? {
        guard let marker = log.range(of: "crop=") else { return nil }
        let values = log[marker.upperBound...]
            .split(whereSeparator: { $0 == Character(":") || $0 == Character(" ") || $0 == Character("\n") })
            .prefix(4)
            .compactMap { Int($0) }
        guard values.count == 4 else { return nil }
        return DetectedCrop(width: values[0], height: values[1], x: values[2], y: values[3])
    }

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
        _ = withMpv { mpv in
            mpv_set_property_string(mpv, "video-crop", signature)
        }
    }

    enum VideoCropMode { case none, square }

    private struct VideoDims: Sendable {
        var width: Int64
        var height: Int64
        var hasVid: Bool
    }

    private func setVideoCrop(_ mode: VideoCropMode) {
        switch mode {
        case .none:
            _ = withMpv { mpv in
                mpv_set_property_string(mpv, "video-crop", "")
            }
        case .square:
            let dims: VideoDims = withMpv { mpv in
                var w = Int64(0), h = Int64(0)
                mpv_get_property(mpv, "video-params/w", MPV_FORMAT_INT64, &w)
                mpv_get_property(mpv, "video-params/h", MPV_FORMAT_INT64, &h)
                var vid: UnsafeMutablePointer<CChar>?
                defer { if let vid { mpv_free(vid) } }
                let hasVid = mpv_get_property(mpv, "vid", MPV_FORMAT_STRING, &vid) == 0
                    && vid.map { String(cString: $0) != "no" } ?? false
                return VideoDims(width: w, height: h, hasVid: hasVid)
            } ?? VideoDims(width: 0, height: 0, hasVid: false)
            if dims.width > 0, dims.height > 0 {
                let side = min(dims.width, dims.height)
                _ = withMpv { mpv in
                    mpv_set_property_string(mpv, "video-crop", "\(side)x\(side)")
                }
            } else if dims.hasVid {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    self.setVideoCrop(.square)
                }
            }
        }
    }

    private func loadFileReplacing(_ url: String, startAt: TimeInterval = 0) {
        pendingResumeAt = startAt
        Log.player.debug("TRANSITION loadFileReplacing startAt=\(startAt) url=\(url.prefix(80))")
        withMpv { mpv in
            let args = ["loadfile", url, "replace"]
            _ = args.withUnsafeCArg { mpv_command(mpv, $0) }
        }
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
    func setNowPlayingMetadata() {
        assertAudioSession()
        let np = NowPlaying.shared
        nowPlayingInfo.removeAll()

        let liveDur = withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
        let duration = liveDur > 0 ? liveDur : np.duration
        if duration > 0 { np.duration = duration }

        let livePos = withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
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

    func updateNowPlayingArtwork() {
        let np = NowPlaying.shared
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func updateNowPlayingProgress() {
        let props: (dur: Double, pos: Double)? = withMpv { mpv in
            var dur = Double(0)
            mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur)
            var pos = Double(0)
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos)
            return (dur, pos)
        }
        guard let props, props.dur > 0 else { return }
        let np = NowPlaying.shared

        var info = nowPlayingInfo
        info[MPMediaItemPropertyPlaybackDuration] = props.dur
        np.duration = props.dur
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = props.pos
        np.currentTime = props.pos
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
                "playing=\(np.isPlaying) pos=\(props.pos) keys=\(info.keys.count)"
            )
        }
    }

    private static var lastBackgroundHeartbeat = Date.distantPast
}

// MARK: - Remote commands

extension PlayerController {
    nonisolated static func registerRemoteControlSupport() {
        MainActor.assumeIsolated {
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
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.logBackgroundSnapshot("resignActive") }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.logBackgroundSnapshot("enterBackground")
            }
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
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.logBackgroundSnapshot("becomeActive") }
        }
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
