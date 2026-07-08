//
//  PlaylistDetailView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

// MARK: - View Model

@MainActor
@Observable
final class PlaylistDetailViewModel {
    let playlistId: String
    var playlist: PlaylistDetailInfo?
    var isLoading = true
    var error: Error?

    private let innerTube = InnerTube.shared
    let autoRoute: AutoPlaylistRoute?
    var autoSongSort: LibrarySongSort = .recentlyAdded
    var autoTopPeriod: TopPeriod = .allTime

    init(playlistId: String) {
        self.playlistId = playlistId
        self.autoRoute = nil
    }

    init(autoPlaylistRoute: AutoPlaylistRoute) {
        self.playlistId = ""
        self.autoRoute = autoPlaylistRoute
    }

    /// Fetches playlist browse page from InnerTube and parses the response.
    /// Prependes "VL" to the playlistId if not already present (required by the browse endpoint).
    func load() async {
        if let route = autoRoute {
            await loadAutoPlaylist(route: route)
            return
        }

        isLoading = true
        error = nil

        do {
            let browseId = playlistId.hasPrefix("VL") ? playlistId : "VL\(playlistId)"
            let json = try await innerTube.browse(browseId: browseId)
            let parsed = Self.parsePlaylistDetail(from: json, playlistId: playlistId)
            let hasAvatar = parsed.authorAvatarUrl != nil
            print("[PlaylistDetail] title=\(parsed.title) author=\(parsed.authorName ?? "nil") avatar=\(hasAvatar) cnt=\(parsed.songCount) dur=\(parsed.duration) songs=\(parsed.songs.count)")
            playlist = parsed
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func loadAutoPlaylist(route: AutoPlaylistRoute) async {
        isLoading = true
        error = nil
        print("[PlaylistDetail] Loading auto-playlist route=\(route)")

        do {
            let entities: [SongEntity]
            let title: String
            switch route {
            case .likedSongs:
                title = "Liked Songs"
                print("[PlaylistDetail] Fetching liked songs with sort=\(autoSongSort)")
                entities = try await DatabaseService.shared.fetchAllLikedSongs(sort: autoSongSort)
            case .topSongs(let limit):
                title = "My Top \(limit)"
                print("[PlaylistDetail] Fetching top songs limit=\(limit) period=\(autoTopPeriod.rawValue)")
                entities = try await DatabaseService.shared.fetchTopSongs(limit: limit, from: autoTopPeriod.dateFrom, to: Date())
            }
            print("[PlaylistDetail] Fetched \(entities.count) song entities")

            var songs = entities.map { SongItem(entity: $0) }
            print("[PlaylistDetail] songs count=\(songs.count)")

            // Resolve missing durations in background
            let emptyDurationIds = songs.filter { $0.duration <= 0 }.map { $0.videoId }
            if !emptyDurationIds.isEmpty {
                print("[PlaylistDetail] Resolving durations for \(emptyDurationIds.count) songs")
                await withTaskGroup(of: (String, Int).self) { group in
                    for videoId in emptyDurationIds {
                        guard !DurationCache.isPending(videoId) else { continue }
                        if let cached = DurationCache.get(videoId), cached > 0 { continue }
                        DurationCache.markPending(videoId)
                        group.addTask {
                            do {
                                let d = try await InnerTube.shared.fetchDuration(videoId: videoId)
                                DurationCache.set(videoId, d)
                                return (videoId, d)
                            } catch {
                                DurationCache.clearPending(videoId)
                                return (videoId, 0)
                            }
                        }
                    }
                }
                for i in songs.indices where songs[i].duration <= 0 {
                    if let cached = DurationCache.get(songs[i].videoId), cached > 0 {
                        songs[i].duration = cached
                    }
                }
                print("[PlaylistDetail] Durations resolved")
            }

            let totalDuration = songs.reduce(0) { $0 + $1.duration }
            print("[PlaylistDetail] totalDuration=\(totalDuration)")

            playlist = PlaylistDetailInfo(
                title: title,
                authorName: nil,
                authorBrowseId: nil,
                authorAvatarUrl: nil,
                descriptionText: nil,
                songCount: songs.count,
                duration: totalDuration,
                thumbnailUrl: nil,
                playlistId: "",
                songs: songs
            )
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Parser

extension PlaylistDetailViewModel {
    /// Parses InnerTube browse JSON into a PlaylistDetailInfo.
    /// Extracts header metadata (title, author, song count, duration, thumbnail, description)
    /// from musicDetailHeaderRenderer and songs from musicPlaylistShelfRenderer or musicShelfRenderer.
    static func parsePlaylistDetail(from json: [String: Any], playlistId: String) -> PlaylistDetailInfo {
        var title = "Unknown Playlist"
        var authorName: String?
        var authorBrowseId: String?
        var authorAvatarUrl: String?
        var descriptionText: String?
        var songCount = 0
        var duration = 0
        var thumbnailUrl: String?
        var songs: [SongItem] = []

        let contents = json["contents"] as? [String: Any]
        let singleColumn = contents?["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let twoColumn = contents?["twoColumnBrowseResultsRenderer"] as? [String: Any]

        let tabsArray: [[String: Any]]? = {
            if let tabs = twoColumn?["tabs"] as? [[String: Any]] { return tabs }
            if let tabs = singleColumn?["tabs"] as? [[String: Any]] { return tabs }
            return nil
        }()
        let firstTabSectionInner = tabsArray?
            .first
            .flatMap { $0["tabRenderer"] as? [String: Any] }
            .flatMap { $0["content"] as? [String: Any] }
            .flatMap { $0["sectionListRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
        let firstTabSection = firstTabSectionInner
            .flatMap { $0["itemSectionRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
            ?? firstTabSectionInner

        let headerRenderer: [String: Any]? =
            firstTabSection?["musicResponsiveHeaderRenderer"] as? [String: Any]
            ?? (firstTabSection?["musicEditablePlaylistDetailHeaderRenderer"] as? NSDictionary)
                .flatMap { ($0 as? [String: Any]) }
                .flatMap { ($0["header"] as? NSDictionary) as? [String: Any] }
                .flatMap { $0["musicDetailHeaderRenderer"] as? [String: Any]
                        ?? $0["musicResponsiveHeaderRenderer"] as? [String: Any] }
            ?? (json["header"] as? [String: Any]).flatMap {
                $0["musicDetailHeaderRenderer"] as? [String: Any]
                ?? $0["musicResponsiveHeaderRenderer"] as? [String: Any]
            }

        if let detailHeader = headerRenderer {
            title = DetailParser.extractRunsText(detailHeader["title"] as? [String: Any]) ?? title
            thumbnailUrl = DetailParser.extractMusicThumbnail(detailHeader)

            descriptionText = detailHeader["description"]
                .flatMap { $0 as? [String: Any] }
                .flatMap { DetailParser.extractRunsText($0) }

            // Author from straplineTextOne
            if let strapline = detailHeader["straplineTextOne"] as? [String: Any],
               let runs = strapline["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String {
                authorName = text
                authorBrowseId = (firstRun["navigationEndpoint"] as? [String: Any])
                    .flatMap { $0["browseEndpoint"] as? [String: Any] }
                    .flatMap { $0["browseId"] as? String }
            }

            // Author from facepile (editable/self-authored playlists)
            if authorName == nil,
               let facepile = detailHeader["facepile"] as? [String: Any],
               let stack = facepile["avatarStackViewModel"] as? [String: Any] {
                authorName = (stack["text"] as? [String: Any])?["content"] as? String
                authorBrowseId = (stack["rendererContext"] as? [String: Any])
                    .flatMap { $0["commandContext"] as? [String: Any] }
                    .flatMap { $0["onTap"] as? [String: Any] }
                    .flatMap { $0["innertubeCommand"] as? [String: Any] }
                    .flatMap { $0["browseEndpoint"] as? [String: Any] }
                    .flatMap { $0["browseId"] as? String }
                print("[Parser] facepile authorName=\(authorName ?? "nil") authorBrowseId=\(authorBrowseId ?? "nil")")
                if let avatars = stack["avatars"] as? [[String: Any]],
                   let firstAvatar = avatars.first,
                   let vm = firstAvatar["avatarViewModel"] as? [String: Any],
                   let image = vm["image"] as? [String: Any],
                   let sources = image["sources"] as? [[String: Any]],
                   let firstSource = sources.first,
                   let url = firstSource["url"] as? String {
                    authorAvatarUrl = url
                    print("[Parser] facepile avatar URL: \(url)")
                } else {
                    print("[Parser] facepile found but failed to extract avatar URL")
                    print("[Parser] facepile stack keys: \(stack.keys)")
                    if let avatars = stack["avatars"] {
                        print("[Parser] avatars type: \(type(of: avatars))")
                    }
                }
            }

            // Author from subtitle runs (fallback)
            if authorName == nil,
               let subtitle = detailHeader["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed == "•" { continue }
                    if let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                       let bind = navEndpoint["browseEndpoint"] as? [String: Any],
                       let bid = bind["browseId"] as? String {
                        authorName = trimmed; authorBrowseId = bid; break
                    } else if authorName == nil {
                        authorName = trimmed
                    }
                }
            }

            // Song count / duration from secondSubtitle
            if let secondSubtitle = detailHeader["secondSubtitle"] as? [String: Any],
               let runs = secondSubtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("song") || trimmed.contains("Song") ||
                       trimmed.contains("track") || trimmed.contains("Track") ||
                       trimmed.contains("video") || trimmed.contains("Video") {
                        if let count = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first {
                            songCount = count
                            print("[Parser] parsed songCount=\(songCount)")
                        }
                    } else if trimmed.contains(":") {
                        duration = DetailParser.parseDuration(trimmed)
                        print("[Parser] parsed duration=\(duration) from '\(trimmed)'")
                    } else {
                        let lower = trimmed.lowercased()
                        if lower.hasSuffix("min") || lower.hasSuffix("mins") || lower.hasSuffix("minute") || lower.hasSuffix("minutes") {
                            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                            if let minutes = nums.first {
                                duration = minutes * 60
                                print("[Parser] parsed duration=\(duration) from '\(trimmed)' (text minutes)")
                            }
                        } else if lower.hasSuffix("hour") || lower.hasSuffix("hours") || lower.hasSuffix("hr") || lower.hasSuffix("hrs") {
                            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                            if let hours = nums.first {
                                duration = hours * 3600
                                print("[Parser] parsed duration=\(duration) from '\(trimmed)' (text hours)")
                            }
                        }
                    }
                }
            }
        }

        // --- Songs ---
        // Two-column layout: songs live in secondaryContents, not in the tabs.
        func parseSongsFromShelf(_ shelfDict: [String: Any]) -> [SongItem] {
            var result: [SongItem] = []
            let items: [[String: Any]]? =
                (shelfDict["musicPlaylistShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
                ?? (shelfDict["musicShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
            for itemDict in items ?? [] {
                if let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any],
                   let song = SongItem.from(renderer) {
                    result.append(song)
                }
            }
            return result
        }

        if let twoCol = twoColumn {
            // Songs are in secondaryContents
            if let secondary = twoCol["secondaryContents"] as? [String: Any],
               let sectionList = secondary["sectionListRenderer"] as? [String: Any],
               let secondarySection = sectionList["contents"] as? [[String: Any]] {
                for section in secondarySection {
                    // Unwrap itemSectionRenderer wrapper
                    let unwrapped = (section["itemSectionRenderer"] as? [String: Any])
                        .flatMap { ($0["contents"] as? [[String: Any]])?.first }
                        ?? section
                    songs += parseSongsFromShelf(unwrapped)
                }
            }
        } else if let singleCol = singleColumn {
            if let tabs = singleCol["tabs"] as? [[String: Any]],
               let sections = tabs.first
                .flatMap({ $0["tabRenderer"] as? [String: Any] })
                .flatMap({ $0["content"] as? [String: Any] })
                .flatMap({ $0["sectionListRenderer"] as? [String: Any] })
                .flatMap({ $0["contents"] as? [[String: Any]] }) {
                for section in sections {
                    let unwrapped = (section["itemSectionRenderer"] as? [String: Any])
                        .flatMap { ($0["contents"] as? [[String: Any]])?.first }
                        ?? section
                    songs += parseSongsFromShelf(unwrapped)
                }
            }
        }

        // Use actual song data for total duration (more precise than header)
        if songCount == 0 { songCount = songs.count }
        let songDuration = songs.reduce(0) { $0 + $1.duration }
        if songDuration > 0 {
            print("[Parser] computed duration from songs: \(songDuration) (header had: \(duration))")
            duration = songDuration
        }

        return PlaylistDetailInfo(
            title: title,
            authorName: authorName,
            authorBrowseId: authorBrowseId,
            authorAvatarUrl: authorAvatarUrl,
            descriptionText: descriptionText,
            songCount: songCount,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            playlistId: playlistId,
            songs: songs
        )
    }
}

// MARK: - View

struct PlaylistDetailView: View {
    let playlistId: String
    @State private var viewModel: PlaylistDetailViewModel

    @Environment(\.dismiss) private var dismiss

    init(playlistId: String) {
        self.playlistId = playlistId
        _viewModel = State(initialValue: PlaylistDetailViewModel(playlistId: playlistId))
    }

    init(autoPlaylistRoute: AutoPlaylistRoute) {
        self.playlistId = ""
        _viewModel = State(initialValue: PlaylistDetailViewModel(autoPlaylistRoute: autoPlaylistRoute))
    }

    var body: some View {
        ScrollView {
            Group {
                if viewModel.isLoading {
                    loadingView
                        .containerRelativeFrame(.vertical)
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "Couldn't load playlist",
                        systemImage: "exclamationmark.circle",
                        description: Text(error.localizedDescription)
                    )
                    .containerRelativeFrame(.vertical)
                } else if let playlist = viewModel.playlist {
                    playlistContent(for: playlist)
                } else {
                    ContentUnavailableView(
                        "No playlist data",
                        systemImage: "music.note.list",
                        description: Text("Could not parse playlist details")
                    )
                    .containerRelativeFrame(.vertical)
                }
            }
        }
        .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.playlist == nil)
        .navigationTitle(viewModel.playlist?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.isLoading else { return }
            await viewModel.load()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading playlist...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func playlistContent(for playlist: PlaylistDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: playlist)
                .padding(.bottom, 8)

            if playlist.songs.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Text("No songs found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                songList(for: playlist)
            }
        }
    }

    @ViewBuilder
    private func header(for playlist: PlaylistDetailInfo) -> some View {
        VStack(spacing: 12) {
            // Playlist artwork
            if let thumbnailUrl = playlist.thumbnailUrl {
                AsyncImageView(url: thumbnailUrl)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 200, height: 200)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            }

            // Playlist title
            Text(playlist.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Metadata: song count | duration
            let metaParts = metaStrings(for: playlist)
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " | "))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            // Author row: avatar + name, clickable → artist detail
            if let authorName = playlist.authorName {
                Group {
                    if let authorId = playlist.authorBrowseId {
                        NavigationLink(value: DetailRoute.artist(browseId: authorId)) {
                            authorRow(name: authorName, avatarUrl: playlist.authorAvatarUrl)
                        }
                        .buttonStyle(.plain)
                    } else {
                        authorRow(name: authorName, avatarUrl: playlist.authorAvatarUrl)
                    }
                }
            }

            // Description (only if fetched, no fallback)
            if let desc = playlist.descriptionText, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
            }

            // Action buttons: shuffle, play
            HStack(spacing: 20) {
                Button(action: { shufflePlay(playlist) }) {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)

                Button(action: { playAll(playlist) }) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func authorRow(name: String, avatarUrl: String?) -> some View {
        HStack(spacing: 8) {
            if let avatarUrl {
                AsyncImageView(url: avatarUrl)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func songList(for playlist: PlaylistDetailInfo) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(playlist.songs.enumerated()), id: \.offset) { index, song in
                Button(action: { playSong(song, in: playlist) }) {
                    PlaylistSongRow(song: song)
                }
                .buttonStyle(.plain)

                if index < playlist.songs.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
    }

    // MARK: - Actions

    private func playAll(_ playlist: PlaylistDetailInfo) {
        guard !playlist.songs.isEmpty else { return }
        let first = playlist.songs[0]
        NowPlaying.shared.setQueue(playlist.songs, startIndex: 0)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
            } catch {
            }
        }
    }

    private func shufflePlay(_ playlist: PlaylistDetailInfo) {
        guard !playlist.songs.isEmpty else { return }
        let shuffled = playlist.songs.shuffled()
        let first = shuffled[0]
        NowPlaying.shared.setQueue(shuffled, startIndex: 0)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
            } catch {
            }
        }
    }

    private func playSong(_ song: SongItem, in playlist: PlaylistDetailInfo) {
        guard let index = playlist.songs.firstIndex(where: { $0.videoId == song.videoId }) else { return }
        NowPlaying.shared.setQueue(playlist.songs, startIndex: index)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
            }
        }
    }

    // MARK: - Helpers

    /// Builds metadata strings like "50 songs • 3:25:10"
    private func metaStrings(for playlist: PlaylistDetailInfo) -> [String] {
        var parts: [String] = []
        if playlist.songCount > 0 { parts.append("\(playlist.songCount) song\(playlist.songCount != 1 ? "s" : "")") }
        if playlist.duration > 0 { parts.append(playlist.duration.formattedDuration) }
        return parts
    }
}

// MARK: - Song Row

struct PlaylistSongRow: View {
    let song: SongItem

    @State private var resolvedDuration: Int = 0

    private var effectiveDuration: Int {
        song.duration > 0 ? song.duration : resolvedDuration
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                let artistStr = song.artists.map(\.name).joined(separator: ", ")
                let durationStr = effectiveDuration.formattedDuration
                let subtitleText = artistStr.isEmpty ? durationStr : (durationStr.isEmpty ? artistStr : "\(artistStr) • \(durationStr)")

                Text(subtitleText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .task { await resolveDuration() }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            guard let vid = notification.userInfo?["videoId"] as? String, vid == song.videoId else { return }
            resolvedDuration = DurationCache.get(vid) ?? 0
        }
    }

    private func resolveDuration() async {
        guard song.duration <= 0 else { return }
        let vid = song.videoId
        if let cached = DurationCache.get(vid), cached > 0 {
            resolvedDuration = cached
            return
        }
        guard !DurationCache.isPending(vid) else { return }
        DurationCache.markPending(vid)
        do {
            let duration = try await InnerTube.shared.fetchDuration(videoId: vid)
            resolvedDuration = duration
        } catch {
            DurationCache.clearPending(vid)
        }
    }
}
