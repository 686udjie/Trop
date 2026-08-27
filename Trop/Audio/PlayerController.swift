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

final class PlayerController {
    static let shared = PlayerController()

    private var mpv: OpaquePointer?
    private let playbackQueue = DispatchQueue(label: "com.686udjie.PlayerController")
    private var isRunning = false
    private var currentVideoId: String?
    private var pendingVideoId: String?
    private var lastDetectedCrop: String?
    private var detectedCropRepeatCount = 0
    private var currentLoudnessDb: Double?
    /// URL stored when play() is called before mpv_initialize() completes.
    /// Drained by the event loop on its first iteration.
    private var pendingURL: String?

    /// Metal layer mpv renders into; created up-front so `wid` is valid at init.
    /// `contentsScale` is set from the window's screen when hosted (MpvVideoUIView).
    var videoLayer: CAMetalLayer = {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.contentsScale = 1
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 180
        )
        layer.frame = bounds
        layer.drawableSize = CGSize(width: bounds.width * layer.contentsScale, height: bounds.height * layer.contentsScale)
        return layer
    }()

    private func clearVideoLayer() {
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

    let playState = CurrentValueSubject<State, Never>(.stopped)

    /// Resume position (seconds) applied via `seek` after the next file loads.
    private var pendingResumeAt: TimeInterval = 0

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
        // Discard any frame still held in the shared video layer
        if hasPresentedVideo {
            clearVideoLayer()
        }
        if let videoId {
            await PlaybackStateService.shared.startTracking(videoId: videoId)
        }

        guard let mpv = self.mpv else {
            // mpv_initialize hasn't finished yet — park the URL so the event
            // loop loads it on its first wake.
            Log.player.info("mpv not ready yet, parking URL for deferred load")
            pendingURL = url.absoluteString
            return
        }

        // Apply per-track loudness normalization now that currentLoudnessDb
        // reflects the incoming track (play() sets it above).
        applyPlaybackSettings()

        // Never set `vid=no` here — it tears down gpu-next's device mid-flight
        // and crashes MoltenVK. The audio-only stream has no video track, so
        // just clear any stale crop from the previous song.
        setVideoCrop(.none)

        pendingVideoId = videoId
        Log.player.info(
            "TRANSITION play videoId=\(videoId ?? "nil") isNewSong=\(isNewSong) muxedActive=\(muxedActive) url=\(url.absoluteString.prefix(80))"
        )
        let cmdResult = ["loadfile", url.absoluteString, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
        Log.player.info("mpv_command loadfile result=\(cmdResult)")
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
                Log.player.error("mpv_create failed")
                return
            }
            // NOTE: self.mpv is intentionally NOT set here.
            // It is only assigned after mpv_initialize() succeeds so that
            // play() cannot call mpv C functions on an uninitialized handle,
            // which would race with mpv_initialize() and crash.

            // Enable log output before anything else so we capture init errors.
            mpv_request_log_messages(mpv, "warn")

            // Audio-only startup: vo=null avoids spinning up MoltenVK/Vulkan during
            // mpv_initialize, which crashes on the simulator and is wasted work
            // for pure audio streams. Video renderer is switched in lazily via
            // setVideoTrack() when the user enters video mode.
            mpv_set_option_string(mpv, "vo", "null")
            mpv_set_option_string(mpv, "vid", "no")
            mpv_set_option_string(mpv, "force-window", "no")

            // Simulator can't use VideoToolbox hwdec; real devices can.
            #if targetEnvironment(simulator)
            mpv_set_option_string(mpv, "hwdec", "no")
            // audio-exclusive mode crashes on the simulator (AudioUnit exclusive
            // routing requires a real audio output device). Disable it.
            mpv_set_option_string(mpv, "audio-exclusive", "no")
            #else
            mpv_set_option_string(mpv, "hwdec", "videotoolbox")
            // Prevent mpv's ao_audiounit from setting MixWithOthers, which causes
            // iOS to fade lock-screen / Control Center media controls.
            mpv_set_option_string(mpv, "audio-exclusive", "yes")
            #endif

            mpv_set_option_string(mpv, "keep-open", "no")
            mpv_set_option_string(mpv, "cache", "yes")
            mpv_set_option_string(mpv, "cache-secs", "120")
            mpv_set_option_string(mpv, "demuxer-max-bytes", "200M")
            mpv_set_option_string(mpv, "gapless-audio", "yes")

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

            // Post-init runtime properties (safe to set after mpv_initialize).
            if let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
                mpv_set_property_string(mpv, "tls-ca-file", caPath)
                Log.player.info("mpv tls-ca-file set: \(caPath)")
            } else {
                Log.player.warning("mpv cacert.pem not found in main bundle")
            }
            mpv_set_property_string(
                mpv,
                "user-agent",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            )
            // Video display options — harmless with vo=null, take effect when vo switches.
            mpv_set_property_string(mpv, "background", "0x00000000")
            mpv_set_property_string(mpv, "video-unscaled", "no")
            mpv_set_property_string(mpv, "keepaspect", "no")

            mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
            // First decoded frame size; > 0 means the video is actually
            // decoding/rendering. Used to reveal the video only once it can
            // show a real frame instead of a blank square.
            mpv_observe_property(mpv, 1, "video-params/w", MPV_FORMAT_INT64)

            // Publish the handle only after successful initialization so play()
            // never sees a partially-initialized mpv instance.
            self.mpv = mpv
            Log.player.info("mpv handle published — event loop starting")

            self.applyPlaybackSettings()

            // Drain any URL that was queued while mpv was initializing.
            if let url = self.pendingURL {
                self.pendingURL = nil
                Log.player.info("mpv ready: loading deferred URL \(url.prefix(80))")
                ["loadfile", url, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
            }

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
                if let prop = event.pointee.data?.load(as: mpv_event_log_message.self),
                   let textPtr = prop.text {
                    let text = String(cString: textPtr)
                    let prefix = prop.prefix.map { String(cString: $0) } ?? ""
                    let level = prop.level.map { String(cString: $0) } ?? ""
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Log.mpv.debug("[\(prefix)] [\(level)] \(trimmed)")
                        if let crop = self.detectedCrop(from: trimmed) {
                            DispatchQueue.main.async {
                                self.applyDetectedCrop(crop)
                            }
                        }
                    }
                }
            case MPV_EVENT_FILE_LOADED:
                var pauseFlag = Int32(1)
                mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
                let actuallyPlaying = pauseFlag == 0
                Log.player.debug("TRANSITION FILE_LOADED videoId=\(self.pendingVideoId ?? "nil") playing=\(actuallyPlaying)")
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
            case MPV_EVENT_PROPERTY_CHANGE:
                if let prop = event.pointee.data?.load(as: mpv_event_property.self),
                   let namePtr = prop.name {
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
                    } else if name == "video-params/w",
                              prop.format == MPV_FORMAT_INT64 {
                        let width = prop.data?.assumingMemoryBound(to: Int64.self)
                        if let width, width.pointee > 0 {
                            // First frame decoded in video mode: now reveal it so
                            // the artwork (not a blank square) shows until then.
                            // `muxedActive`/`videoId` are main-actor state, so the
                            // staleness check happens INSIDE the main dispatch — a
                            // late event from a replaced song must not reveal the
                            // video layer for the current (possibly audio-only) song.
                            Log.player.debug("TRANSITION video-params/w=\(width.pointee) videoId=\(self.currentVideoId ?? "nil")")
                            DispatchQueue.main.async {
                                let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
                                guard ok else { return }
                                if self.hasPresentedVideo {
                                    self.clearVideoLayer()
                                }
                                NowPlaying.shared.isVideoMode = true
                                self.hasPresentedVideo = true
                            }
                        }
                    }
                }
            case MPV_EVENT_START_FILE:
                Log.player.debug("TRANSITION START_FILE")
            case MPV_EVENT_END_FILE:
                let stoppedVideoId = self.currentVideoId
                let endFile = event.pointee.data?.load(as: mpv_event_end_file.self)
                let reason = endFile?.reason ?? MPV_END_FILE_REASON_EOF
                let errCode = endFile?.error ?? 0
                let errStr = mpv_error_string(errCode).map { String(cString: $0) } ?? "unknown"
                let isEof = reason == MPV_END_FILE_REASON_EOF
                // reason==STOP fires whenever we intentionally replace the current
                // file (entering video mode, next/prev, mid-play re-resolve).
                // Treating it as a failure would spuriously re-resolve and bounce
                // out of video mode. Only genuine errors run failure recovery.
                let isFailure = reason == MPV_END_FILE_REASON_ERROR
                Log.player.debug(
                    "TRANSITION END_FILE reason=\(reason) error=\(errCode)(\(errStr)) isEof=\(isEof) isFailure=\(isFailure) stoppedVideoId=\(stoppedVideoId ?? "nil")"
                )
                // Only a genuine end-of-file or error stops tracking; an
                // intentional replace (STOP) must not kill the NEW song's
                // tracking session, which play() has already started.
                if isEof || isFailure, stoppedVideoId != nil {
                    Task { await PlaybackStateService.shared.stopTracking() }
                }
                self.currentVideoId = nil
                if isEof || isFailure {
                    DispatchQueue.main.async {
                        self.playState.send(.stopped)
                        NowPlaying.shared.stopped(videoId: stoppedVideoId, isEof: isEof)
                    }
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

    // MARK: - App Volume

    /// Sets the app-level playback volume (0...1). Applied as mpv software
    /// gain — never touches the system/media volume.
    func setPlayerVolume(_ volume: Double) {
        SettingsStore.shared.playerVolume = min(1, max(0, volume))
        applyPlayerVolume()
    }

    /// Pushes the persisted volume to the running mpv instance.
    func applyPlayerVolume() {
        guard let mpv else { return }
        var val = Double(SettingsStore.shared.playerVolume * 100)
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &val)
    }

    // MARK: - Playback Settings (equalizer / filters)

    /// Applies the equalizer, gapless, and normalization settings to the
    /// running mpv instance. Safe to call repeatedly; the UI calls it whenever
    /// the user changes any playback setting.
    ///
    /// The equalizer uses mpv's `firequalizer` filter with one gain entry per
    /// band frequency, matching the on-screen line graph.
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
        if result < 0 {
            Log.player.error("Failed to set af chain '\(chain)': mpv error \(result)")
        }

        applyPlayerVolume()
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    @MainActor
    func seek(to time: TimeInterval) {
        guard let mpv = self.mpv else { return }
        var val = time
        let result = mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
        if result < 0 {
            Log.player.error("seek failed: mpv error \(result)")
        }
    }

    @MainActor
    func togglePlayPause() {
        guard let mpv = self.mpv else { return }
        let willBePlaying = playState.value == .paused || playState.value == .stopped
        var flag: Int32 = willBePlaying ? 0 : 1
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        playState.send(willBePlaying ? .playing : .paused)
        NowPlaying.shared.isPlaying = willBePlaying
        updateNowPlayingProgress()
    }

    /// Video mode loads the muxed stream once and keeps it resident; later
    /// toggles are pure SwiftUI opacity (no `loadfile`/`vid` switch/device
    /// teardown). `vid=auto` stays selected so re-enabling is instant.
    private var videoModeSwitchInFlight = false
    private var loadedMuxedURL: String?
    private var muxedActive = false
    /// videoId the currently-loaded muxed/EDL stream belongs to, so late mpv
    /// events (video-params/w from a replaced file) can't reveal video mode
    /// for a different song. All access on the main actor.
    private var muxedVideoId: String?
    /// True once any video frame has been presented to the shared layer. Until
    /// then the layer can't hold a stale frame, so clearing it is unnecessary
    /// AND dangerous: on the first video the layer's device is only being set
    /// up by MoltenVK, and presenting our own drawable mid-init leaves the
    /// video permanently blank. All access on the main actor.
    private var hasPresentedVideo = false

    @MainActor
    func setVideoMode() {
        guard let videoId = NowPlaying.shared.videoId else { return }
        // Stream already loaded and rendering: pure UI flip, nothing to load.
        if muxedActive {
            NowPlaying.shared.isVideoMode = true
            return
        }
        guard !videoModeSwitchInFlight else { return }
        videoModeSwitchInFlight = true
        Task {
            defer { videoModeSwitchInFlight = false }
            do {
                let resumeAt = self.currentTime
                let url: String
                if let loaded = self.loadedMuxedURL {
                    url = loaded
                } else {
                    url = try await PlaybackManager.shared.resolveMuxedURL(videoId: videoId)
                    guard NowPlaying.shared.videoId == videoId else { return }
                    self.loadedMuxedURL = url
                }
                guard NowPlaying.shared.videoId == videoId else { return }
                self.setVideoTrack()
                Log.player.debug("TRANSITION entering video mode videoId=\(videoId) url=\(url.prefix(80))")
                self.muxedVideoId = videoId
                self.loadFileReplacing(url, startAt: resumeAt)
                self.muxedActive = true
            } catch {
                Log.player.error("setVideoMode failed: \(error)")
                NowPlaying.shared.isVideoMode = false
            }
        }
    }

    /// Resolves and caches the video source in the background so toggling video
    /// mode is instant. Discarded if the song changes before it finishes.
    @MainActor
    func preloadVideoURL() {
        guard loadedMuxedURL == nil else { return }
        guard let videoId = NowPlaying.shared.videoId else { return }
        Task {
            do {
                let url = try await PlaybackManager.shared.resolveMuxedURL(videoId: videoId)
                guard NowPlaying.shared.videoId == videoId, self.loadedMuxedURL == nil else { return }
                self.loadedMuxedURL = url
            } catch {
                Log.player.error("Video preload failed: \(error)")
            }
        }
    }

    /// Resets the cached video-mode state after a split-stream died mid-play,
    /// so re-entering video mode re-resolves fresh URLs instead of reusing
    /// stale (possibly expired) ones. Called before audio-only recovery.
    @MainActor
    func handleVideoStreamFailure() {
        guard muxedActive || videoModeSwitchInFlight else { return }
        loadedMuxedURL = nil
        muxedActive = false
        muxedVideoId = nil
        videoModeSwitchInFlight = false
        NowPlaying.shared.isVideoMode = false
    }

    /// Selects the video track (`vid=auto` always) without cropping the source.
    private func setVideoTrack() {
        guard let mpv else { return }
        lastDetectedCrop = nil
        detectedCropRepeatCount = 0
        mpv_set_property_string(mpv, "vo", "gpu-next")
        mpv_set_property_string(mpv, "gpu-api", "vulkan")
        mpv_set_property_string(mpv, "gpu-context", "moltenvk")
        var wid = unsafeBitCast(self.videoLayer, to: Int64.self)
        mpv_set_property(mpv, "wid", MPV_FORMAT_INT64, &wid)
        mpv_set_property_string(mpv, "vid", "auto")
        setVideoCrop(.none)
    }

    private struct DetectedCrop {
        let width: Int
        let height: Int
        let x: Int
        let y: Int
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

    /// Center-crops the video to a square to match the artwork presentation.
    private enum VideoCropMode { case none, square }

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
                // Frame size not known yet; retry once decoded.
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

    /// Loads a new URL into mpv, replacing the current file. `startAt` (seconds)
    /// resumes via `seek` after the file loads (mpv's `start=` option is
    /// unreliable in this build).
    @MainActor
    private func loadFileReplacing(_ url: String, startAt: TimeInterval = 0) {
        guard let mpv else { return }
        pendingResumeAt = startAt
        Log.player.debug("TRANSITION loadFileReplacing startAt=\(startAt) url=\(url.prefix(80))")
        let args = ["loadfile", url, "replace"]
        _ = args.withUnsafeCArg { mpv_command(mpv, $0) }
    }

    @MainActor
    private func applyPendingResumeIfNeeded() {
        guard pendingResumeAt > 0 else { return }
        let target = pendingResumeAt
        pendingResumeAt = 0
        seek(to: target)
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

// MARK: - System Integration (audio session, lock-screen info, remote commands)

extension PlayerController {
    // MARK: - Audio Session

    func assertAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio
            )
            try session.setActive(true)
            Log.player.info("""
            AUDIO_SESSION category=\(session.category.rawValue) active=\(session.isOtherAudioPlaying ? "yes(otherPlaying)" : "yes") \
            outputs=\(session.currentRoute.outputs.map(\.portName).joined(separator: ","))
            """)
        } catch {
            Log.player.error("Failed to assert audio session: \(error)")
        }
    }

    private func logBackgroundSnapshot(_ phase: String) {
        let session = AVAudioSession.sharedInstance()
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        Log.player.info("""
        BG_SNAPSHOT[\(phase)] state=\(playState.value) \
        title=\(nowPlayingInfo[MPMediaItemPropertyTitle] ?? "-") \
        infoKeys=\(info?.keys.count ?? 0) rate=\(info?[MPNowPlayingInfoPropertyPlaybackRate] ?? "-") \
        category=\(session.category.rawValue)
        """)
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
            if playState.value == .playing {
                Task { @MainActor in self.togglePlayPause() }
            }
        case .ended:
            Log.player.info("AUDIO_INTERRUPTION ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    assertAudioSession()
                    if playState.value == .paused {
                        Task { @MainActor in self.togglePlayPause() }
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

        Log.player.info("ROUTE_CHANGE reason=\(reason.rawValue)")
        if reason == .oldDeviceUnavailable {
            if playState.value == .playing {
                Task { @MainActor in self.togglePlayPause() }
            }
        }
    }

    // MARK: - Now Playing Info

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
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        Log.player.info("""
        NOW_PLAYING_PUBLISH title='\(np.title)' artist='\(np.artist)' \
        duration=\(duration) rate=\(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] ?? 0) \
        artwork=\(np.thumbnailUIImage != nil) keys=\(nowPlayingInfo.keys.count)
        """)
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

        // While backgrounded, periodically prove what the system should be
        // seeing. Silence here means the progress timer died with the app
        // suspended — itself a diagnostic.
        if UIApplication.shared.applicationState != .active,
           Date().timeIntervalSince(Self.lastBackgroundHeartbeat) > 2 {
            Self.lastBackgroundHeartbeat = Date()
            Log.player.info("""
            BG_HEARTBEAT appState=\(UIApplication.shared.applicationState.rawValue) \
            playing=\(np.isPlaying) pos=\(pos) keys=\(info.keys.count)
            """)
        }
    }

    private static var lastBackgroundHeartbeat = Date.distantPast

    // MARK: - Remote Commands

    /// Registered at app launch rather than first playback: iOS decides
    /// whether an app may host lock-screen controls partly on remote-event
    /// reception being enabled before backgrounding ever happens.
    static func registerRemoteControlSupport() {
        DispatchQueue.main.async {
            UIApplication.shared.beginReceivingRemoteControlEvents()
            Log.player.info("REMOTE_COMMANDS launch-time beginReceivingRemoteControlEvents")
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND play fired")
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND pause fired")
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
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Log.player.info("REMOTE_COMMAND seek fired to=\(position)")
            Task { @MainActor [weak self] in
                self?.seek(to: position)
                self?.updateNowPlayingProgress()
            }
            return .success
        }

        // Correlate lock/unlock with what the system should be seeing.
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
            // Some iOS builds drop Now Playing info that was published shortly
            // before backgrounding; republish while we are guaranteed alive.
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
