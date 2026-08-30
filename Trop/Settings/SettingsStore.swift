//
//  SettingsStore.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

protocol SettingsOption: CaseIterable, Hashable, Identifiable, RawRepresentable where RawValue == String {
    var displayName: String { get }
}

enum ThemeMode: String, CaseIterable, Identifiable, SettingsOption {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum PlayerBackgroundStyle: String, CaseIterable, Identifiable, SettingsOption {
    case dynamic
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dynamic: return "Album Art"
        case .solid: return "Solid"
        }
    }
}

enum LyricsAlignment: String, CaseIterable, Identifiable, SettingsOption {
    case left
    case center
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var iconName: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }

    var textAlignment: Alignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var multilineTextAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

enum AudioQuality: String, CaseIterable, Identifiable, SettingsOption {
    case auto
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

enum DownloadQuality: String, CaseIterable, Identifiable, SettingsOption {
    case auto
    case high
    case standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High (128–192 kbps)"
        case .standard: return "Standard (64–96 kbps)"
        }
    }
}

struct AccentPreset: Identifiable, Hashable {
    let name: String
    let color: Color

    var id: String { name }

    /// The pre-baked alternate app icon matching this accent, or nil when
    /// the accent equals the default (the primary icon is already Default Blue).
    /// Icons live in "App Icons/" and are named after the accent color.
    var alternateIconName: String? {
        guard name != "Default Blue" else { return nil }
        return name
    }

    static let all: [AccentPreset] = [
        AccentPreset(name: "Default Blue", color: Color(red: 0, green: 0.48, blue: 1)),
        AccentPreset(name: "Red", color: Color(red: 0.91, green: 0.22, blue: 0.22)),
        AccentPreset(name: "Orange", color: Color(red: 0.95, green: 0.45, blue: 0.13)),
        AccentPreset(name: "Amber", color: Color(red: 0.98, green: 0.70, blue: 0.15)),
        AccentPreset(name: "Green", color: Color(red: 0.18, green: 0.72, blue: 0.32)),
        AccentPreset(name: "Teal", color: Color(red: 0.12, green: 0.65, blue: 0.60)),
        AccentPreset(name: "Cyan", color: Color(red: 0.15, green: 0.70, blue: 0.90)),
        AccentPreset(name: "Purple", color: Color(red: 0.60, green: 0.35, blue: 0.90)),
        AccentPreset(name: "Pink", color: Color(red: 0.94, green: 0.35, blue: 0.66)),
        AccentPreset(name: "Indigo", color: Color(red: 0.33, green: 0.40, blue: 0.95)),
        AccentPreset(name: "Lime", color: Color(red: 0.55, green: 0.75, blue: 0.20)),
        AccentPreset(name: "Brown", color: Color(red: 0.62, green: 0.43, blue: 0.30))
    ]
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    // MARK: - Appearance

    var themeMode: ThemeMode {
        didSet { Self.defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    var accentColor: Color = AccentPreset.all[0].color

    var accentName: String {
        didSet {
            Self.defaults.set(accentName, forKey: Keys.accentName)
            accentColor = AccentPreset.all.first { $0.name == accentName }?.color ?? AccentPreset.all[0].color
        }
    }

    var playerBackgroundStyle: PlayerBackgroundStyle {
        didSet { Self.defaults.set(playerBackgroundStyle.rawValue, forKey: Keys.playerBackgroundStyle) }
    }

    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var defaultTab: Int {
        didSet { Self.defaults.set(defaultTab, forKey: Keys.defaultTab) }
    }

    // MARK: - Lyrics appearance

    var lyricsFontSize: Double {
        didSet { Self.defaults.set(lyricsFontSize, forKey: Keys.lyricsFontSize) }
    }

    var lyricsAlignment: LyricsAlignment {
        didSet { Self.defaults.set(lyricsAlignment.rawValue, forKey: Keys.lyricsAlignment) }
    }

    /// Shifts lyric timing by this many seconds (positive = later, negative = earlier).
    var lyricsOffsetSeconds: Double {
        didSet { Self.defaults.set(lyricsOffsetSeconds, forKey: Keys.lyricsOffsetSeconds) }
    }

    /// Shows a progress ring during long instrumental gaps in synced lyrics.
    var showIntervalIndicator: Bool {
        didSet { Self.defaults.set(showIntervalIndicator, forKey: Keys.showIntervalIndicator) }
    }

    /// Displays romanized lyrics for Japanese/Korean/Cyrillic lines when available.
    var romanizeCurrentTrack: Bool {
        didSet { Self.defaults.set(romanizeCurrentTrack, forKey: Keys.romanizeCurrentTrack) }
    }

    // MARK: - Playback

    var equalizerEnabled: Bool {
        didSet { Self.defaults.set(equalizerEnabled, forKey: Keys.equalizerEnabled) }
    }

    /// The id of the selected preset, or "custom" when the user edited bands manually.
    var equalizerPresetID: String {
        didSet { Self.defaults.set(equalizerPresetID, forKey: Keys.equalizerPresetID) }
    }

    /// Current band gains in dB, one per `equalizerFrequencies`.
    var equalizerGains: [Double] {
        didSet { Self.defaults.set(equalizerGains, forKey: Keys.equalizerGains) }
    }

    var audioQuality: AudioQuality {
        didSet { Self.defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality) }
    }

    var audioNormalization: Bool {
        didSet { Self.defaults.set(audioNormalization, forKey: Keys.audioNormalization) }
    }

    var gaplessPlayback: Bool {
        didSet { Self.defaults.set(gaplessPlayback, forKey: Keys.gaplessPlayback) }
    }

    var autoplaySimilar: Bool {
        didSet { Self.defaults.set(autoplaySimilar, forKey: Keys.autoplaySimilar) }
    }

    var persistQueue: Bool {
        didSet { Self.defaults.set(persistQueue, forKey: Keys.persistQueue) }
    }

    var playerVolume: Double {
        didSet { Self.defaults.set(playerVolume, forKey: Keys.playerVolume) }
    }

    var artworkSwipeNavigation: Bool {
        didSet { Self.defaults.set(artworkSwipeNavigation, forKey: Keys.artworkSwipeNavigation) }
    }

    // MARK: - Content

    var hideExplicit: Bool {
        didSet { Self.defaults.set(hideExplicit, forKey: Keys.hideExplicit) }
    }

    var showQuickPicks: Bool {
        didSet { Self.defaults.set(showQuickPicks, forKey: Keys.showQuickPicks) }
    }

    var topListsLength: Int {
        didSet { Self.defaults.set(topListsLength, forKey: Keys.topListsLength) }
    }

    var contentCountry: String {
        didSet { Self.defaults.set(contentCountry, forKey: Keys.contentCountry) }
    }

    // MARK: - Lyrics providers

    var disabledLyricsProviders: Set<String> {
        didSet { Self.defaults.set(disabledLyricsProviders.sorted(), forKey: Keys.disabledLyricsProviders) }
    }

    // MARK: - Privacy

    var trackSearchHistory: Bool {
        didSet { Self.defaults.set(trackSearchHistory, forKey: Keys.trackSearchHistory) }
    }

    var trackPlayHistory: Bool {
        didSet { Self.defaults.set(trackPlayHistory, forKey: Keys.trackPlayHistory) }
    }

    // MARK: - Downloads & storage

    var downloadQuality: DownloadQuality {
        didSet { Self.defaults.set(downloadQuality.rawValue, forKey: Keys.downloadQuality) }
    }

    var wifiOnlyDownloads: Bool {
        didSet { Self.defaults.set(wifiOnlyDownloads, forKey: Keys.wifiOnlyDownloads) }
    }

    var autoDownloadOnLike: Bool {
        didSet { Self.defaults.set(autoDownloadOnLike, forKey: Keys.autoDownloadOnLike) }
    }

    // MARK: - Sync

    var syncArtists: Bool {
        didSet { Self.defaults.set(syncArtists, forKey: Keys.syncArtists) }
    }

    var syncPlaylists: Bool {
        didSet { Self.defaults.set(syncPlaylists, forKey: Keys.syncPlaylists) }
    }

    // MARK: - Integrations

    var lastFMEnabled: Bool {
        didSet { Self.defaults.set(lastFMEnabled, forKey: Keys.lastFMEnabled) }
    }

    var lastFMUpdateNowPlaying: Bool {
        didSet { Self.defaults.set(lastFMUpdateNowPlaying, forKey: Keys.lastFMUpdateNowPlaying) }
    }

    var lastFMScrobbleDelayPercent: Double {
        didSet { Self.defaults.set(lastFMScrobbleDelayPercent, forKey: Keys.lastFMScrobbleDelayPercent) }
    }

    var lastFMMinSongDuration: Double {
        didSet { Self.defaults.set(lastFMMinSongDuration, forKey: Keys.lastFMMinSongDuration) }
    }

    var lastFMScrobbleDelaySeconds: Double {
        didSet { Self.defaults.set(lastFMScrobbleDelaySeconds, forKey: Keys.lastFMScrobbleDelaySeconds) }
    }

    var discordRPCEnabled: Bool {
        didSet { Self.defaults.set(discordRPCEnabled, forKey: Keys.discordRPCEnabled) }
    }

    var discordApplicationId: String {
        didSet { Self.defaults.set(discordApplicationId, forKey: Keys.discordApplicationId) }
    }

    // MARK: - Keys

    private enum Keys {
        static let themeMode = "settings.themeMode"
        static let accentName = "settings.accentName"
        static let playerBackgroundStyle = "settings.playerBackgroundStyle"
        static let defaultTab = "settings.defaultTab"
        static let lyricsFontSize = "settings.lyricsFontSize"
        static let lyricsAlignment = "settings.lyricsAlignment"
        static let lyricsOffsetSeconds = "settings.lyricsOffsetSeconds"
        static let showIntervalIndicator = "settings.showIntervalIndicator"
        static let romanizeCurrentTrack = "settings.romanizeCurrentTrack"
        static let equalizerEnabled = "settings.equalizerEnabled"
        static let equalizerPresetID = "settings.equalizerPresetID"
        static let equalizerGains = "settings.equalizerGains"
        static let audioQuality = "settings.audioQuality"
        static let audioNormalization = "settings.audioNormalization"
        static let gaplessPlayback = "settings.gaplessPlayback"
        static let autoplaySimilar = "settings.autoplaySimilar"
        static let persistQueue = "settings.persistQueue"
        static let playerVolume = "settings.playerVolume"
        static let artworkSwipeNavigation = "settings.artworkSwipeNavigation"
        static let hideExplicit = "settings.hideExplicit"
        static let showQuickPicks = "settings.showQuickPicks"
        static let topListsLength = "settings.topListsLength"
        static let contentCountry = "settings.contentCountry"
        static let disabledLyricsProviders = "settings.disabledLyricsProviders"
        static let trackSearchHistory = "settings.trackSearchHistory"
        static let trackPlayHistory = "settings.trackPlayHistory"
        static let downloadQuality = "settings.downloadQuality"
        static let wifiOnlyDownloads = "settings.wifiOnlyDownloads"
        static let autoDownloadOnLike = "settings.autoDownloadOnLike"
        static let syncArtists = "settings.syncArtists"
        static let syncPlaylists = "settings.syncPlaylists"
        static let lastFMEnabled = "settings.lastFMEnabled"
        static let lastFMUpdateNowPlaying = "settings.lastFMUpdateNowPlaying"
        static let lastFMScrobbleDelayPercent = "settings.lastFMScrobbleDelayPercent"
        static let lastFMMinSongDuration = "settings.lastFMMinSongDuration"
        static let lastFMScrobbleDelaySeconds = "settings.lastFMScrobbleDelaySeconds"
        static let discordRPCEnabled = "settings.discordRPCEnabled"
        static let discordApplicationId = "settings.discordApplicationId"
    }

    private static let defaults: UserDefaults = .standard

    private init() {
        let d = Self.defaults
        themeMode = ThemeMode(rawValue: d.string(forKey: Keys.themeMode) ?? "") ?? .system
        accentColor = AccentPreset.all
            .first { $0.name == (d.string(forKey: Keys.accentName) ?? AccentPreset.all[0].name) }?
            .color ?? AccentPreset.all[0].color
        accentName = d.string(forKey: Keys.accentName) ?? AccentPreset.all[0].name
        playerBackgroundStyle = PlayerBackgroundStyle(rawValue: d.string(forKey: Keys.playerBackgroundStyle) ?? "") ?? .dynamic
        defaultTab = d.object(forKey: Keys.defaultTab) as? Int ?? 0
        lyricsFontSize = d.object(forKey: Keys.lyricsFontSize) as? Double ?? 17
        lyricsAlignment = LyricsAlignment(rawValue: d.string(forKey: Keys.lyricsAlignment) ?? "") ?? .center
        lyricsOffsetSeconds = d.object(forKey: Keys.lyricsOffsetSeconds) as? Double ?? 0
        showIntervalIndicator = d.object(forKey: Keys.showIntervalIndicator) as? Bool ?? true
        romanizeCurrentTrack = d.object(forKey: Keys.romanizeCurrentTrack) as? Bool ?? true
        equalizerEnabled = d.object(forKey: Keys.equalizerEnabled) as? Bool ?? false
        equalizerPresetID = d.string(forKey: Keys.equalizerPresetID) ?? "flat"
        if let saved = d.array(forKey: Keys.equalizerGains) as? [Double], saved.count == equalizerFrequencies.count {
            equalizerGains = saved
        } else {
            equalizerGains = EqualizerPresets.all.first?.gains ?? Array(repeating: 0, count: equalizerFrequencies.count)
        }
        audioQuality = AudioQuality(rawValue: d.string(forKey: Keys.audioQuality) ?? "") ?? .auto
        audioNormalization = d.object(forKey: Keys.audioNormalization) as? Bool ?? false
        gaplessPlayback = d.object(forKey: Keys.gaplessPlayback) as? Bool ?? true
        autoplaySimilar = d.object(forKey: Keys.autoplaySimilar) as? Bool ?? true
        persistQueue = d.object(forKey: Keys.persistQueue) as? Bool ?? false
        playerVolume = d.object(forKey: Keys.playerVolume) as? Double ?? 1
        artworkSwipeNavigation = d.object(forKey: Keys.artworkSwipeNavigation) as? Bool ?? true
        hideExplicit = d.object(forKey: Keys.hideExplicit) as? Bool ?? false
        showQuickPicks = d.object(forKey: Keys.showQuickPicks) as? Bool ?? true
        topListsLength = d.object(forKey: Keys.topListsLength) as? Int ?? 8
        contentCountry = d.string(forKey: Keys.contentCountry) ?? "US"
        disabledLyricsProviders = Set(d.stringArray(forKey: Keys.disabledLyricsProviders) ?? [])
        trackSearchHistory = d.object(forKey: Keys.trackSearchHistory) as? Bool ?? true
        trackPlayHistory = d.object(forKey: Keys.trackPlayHistory) as? Bool ?? true
        downloadQuality = DownloadQuality(rawValue: d.string(forKey: Keys.downloadQuality) ?? "") ?? .auto
        wifiOnlyDownloads = d.object(forKey: Keys.wifiOnlyDownloads) as? Bool ?? false
        autoDownloadOnLike = d.object(forKey: Keys.autoDownloadOnLike) as? Bool ?? false
        syncArtists = d.object(forKey: Keys.syncArtists) as? Bool ?? true
        syncPlaylists = d.object(forKey: Keys.syncPlaylists) as? Bool ?? true
        lastFMEnabled = d.object(forKey: Keys.lastFMEnabled) as? Bool ?? false
        lastFMUpdateNowPlaying = d.object(forKey: Keys.lastFMUpdateNowPlaying) as? Bool ?? true
        lastFMScrobbleDelayPercent = d.object(forKey: Keys.lastFMScrobbleDelayPercent) as? Double
            ?? LastFMDefaults.scrobbleDelayPercent
        lastFMMinSongDuration = d.object(forKey: Keys.lastFMMinSongDuration) as? Double
            ?? LastFMDefaults.scrobbleMinSongDuration
        lastFMScrobbleDelaySeconds = d.object(forKey: Keys.lastFMScrobbleDelaySeconds) as? Double
            ?? LastFMDefaults.scrobbleDelaySeconds
        discordRPCEnabled = d.object(forKey: Keys.discordRPCEnabled) as? Bool ?? false
        discordApplicationId = d.string(forKey: Keys.discordApplicationId) ?? ""
    }
}

// MARK: - Environment Key

private struct SettingsStoreKey: EnvironmentKey {
    static let defaultValue: SettingsStore = .shared
}

extension EnvironmentValues {
    var settingsStore: SettingsStore {
        get { self[SettingsStoreKey.self] }
        set { self[SettingsStoreKey.self] = newValue }
    }
}
