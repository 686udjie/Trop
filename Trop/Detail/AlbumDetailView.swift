//
//  AlbumDetailView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

// MARK: - View Model

@MainActor
@Observable
final class AlbumDetailViewModel {
    let browseId: String
    var album: AlbumDetailInfo?
    var isLoading = true
    var error: Error?

    private let innerTube = InnerTube.shared

    init(browseId: String) {
        self.browseId = browseId
    }

    /// Fetches album browse page from InnerTube and parses the response.
    func load() async {
        print("[AlbumDetailViewModel] Loading album browseId=\(browseId)")
        isLoading = true
        error = nil

        do {
            let json = try await innerTube.browse(browseId: browseId)
            print("[AlbumDetailViewModel] Got browse response, parsing...")
            let parsed = Self.parseAlbumDetail(from: json, browseId: browseId)
            album = parsed
            print("[AlbumDetailViewModel] Parsed album: \(parsed.title), \(parsed.songs.count) songs")
            isLoading = false
        } catch {
            print("[AlbumDetailViewModel] Failed: \(error)")
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Parser

extension AlbumDetailViewModel {
    /// Parses InnerTube browse JSON into an AlbumDetailInfo.
    /// Extracts header metadata (title, artists, year, song count, duration, thumbnail)
    /// from musicDetailHeaderRenderer and songs from musicPlaylistShelfRenderer.
    static func parseAlbumDetail(from json: [String: Any], browseId: String) -> AlbumDetailInfo {
        var title = "Unknown Album"
        var artists: [YTArtist] = []
        var year: Int?
        var songCount = 0
        var duration = 0
        var thumbnailUrl: String?
        var playlistId: String?
        var songs: [SongItem] = []

        let contents = json["contents"] as? [String: Any]

        let singleColumn = contents?["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let twoColumn   = contents?["twoColumnBrowseResultsRenderer"]   as? [String: Any]

        // Resolve first tab section (exists in both layouts)
        let tabsArray: [[String: Any]]? = {
            if let tabs = twoColumn?["tabs"] as? [[String: Any]] { return tabs }
            if let tabs = singleColumn?["tabs"] as? [[String: Any]] { return tabs }
            return nil
        }()
        let firstTabSection: [String: Any]? = tabsArray?
            .first
            .flatMap { $0["tabRenderer"] as? [String: Any] }
            .flatMap { $0["content"] as? [String: Any] }
            .flatMap { $0["sectionListRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }

        // --- Header: musicResponsiveHeaderRenderer (modern two-column albums) ---
        if let responsiveHeader = firstTabSection?["musicResponsiveHeaderRenderer"] as? [String: Any] {
            title = DetailParser.extractRunsText(responsiveHeader["title"] as? [String: Any]) ?? title

            // Artists from straplineTextOne
            if let strapline = responsiveHeader["straplineTextOne"] as? [String: Any],
               let runs = strapline["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    var artistId: String?
                    if let browse = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any] {
                        artistId = browse["browseId"] as? String
                    }
                    artists.append(YTArtist(name: text, id: artistId))
                }
            }
            // Artist fallback from subtitle runs
            if artists.isEmpty,
               let subtitle = responsiveHeader["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed == "•" { continue }
                    var artistId: String?
                    if let browse = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any] {
                        artistId = browse["browseId"] as? String
                    }
                    artists.append(YTArtist(name: trimmed, id: artistId))
                }
            }

            // Year / songCount / duration from secondSubtitle
            if let secondSubtitle = responsiveHeader["secondSubtitle"] as? [String: Any],
               let runs = secondSubtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if let yearVal = Int(trimmed), trimmed.count == 4, yearVal > 1900, yearVal < 2100 {
                        year = yearVal
                    } else if trimmed.contains("song") || trimmed.contains("Song") ||
                              trimmed.contains("track") || trimmed.contains("Track") {
                        let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                        if let count = nums.first { songCount = count }
                    } else if trimmed.contains(":") {
                        duration = DetailParser.parseDuration(trimmed)
                    }
                }
            }

            thumbnailUrl = DetailParser.extractMusicThumbnail(responsiveHeader)
        }

        // --- Header fallback: musicDetailHeaderRenderer (legacy / single-column) ---
        if title == "Unknown Album" {
            let legacyHeader: [String: Any]? =
                (json["header"] as? [String: Any])?["musicDetailHeaderRenderer"] as? [String: Any]

            if let detailHeader = legacyHeader {
                title = DetailParser.extractRunsText(detailHeader["title"] as? [String: Any]) ?? title

                if let subtitle = detailHeader["subtitle"] as? [String: Any],
                   let runs = subtitle["runs"] as? [[String: Any]] {
                    for run in runs {
                        guard let text = run["text"] as? String else { continue }
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || trimmed == "•" { continue }
                        var artistId: String?
                        if let nav = run["navigationEndpoint"] as? [String: Any],
                           let browse = nav["browseEndpoint"] as? [String: Any] {
                            artistId = browse["browseId"] as? String
                        }
                        artists.append(YTArtist(name: trimmed, id: artistId))
                    }
                }

                if let secondSubtitle = detailHeader["secondSubtitle"] as? [String: Any],
                   let runs = secondSubtitle["runs"] as? [[String: Any]] {
                    for run in runs {
                        guard let text = run["text"] as? String else { continue }
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        if let yearVal = Int(trimmed), trimmed.count == 4, yearVal > 1900, yearVal < 2100 {
                            year = yearVal
                        } else if trimmed.contains("song") || trimmed.contains("Song") ||
                                  trimmed.contains("track") || trimmed.contains("Track") {
                            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                            if let count = nums.first { songCount = count }
                        } else if trimmed.contains(":") {
                            duration = DetailParser.parseDuration(trimmed)
                        }
                    }
                }

                if thumbnailUrl == nil { thumbnailUrl = DetailParser.extractMusicThumbnail(detailHeader) }

                // Extract playlistId from menu items (needed for playback queue)
                if let menu = detailHeader["menu"] as? [String: Any],
                   let menuRenderer = menu["menuRenderer"] as? [String: Any],
                   let items = menuRenderer["items"] as? [[String: Any]] {
                    for item in items {
                        if let menuNav = item["menuNavigationItemRenderer"] as? [String: Any],
                           let nav = menuNav["navigationEndpoint"] as? [String: Any],
                           let watch = nav["watchEndpoint"] as? [String: Any],
                           let pid = watch["playlistId"] as? String {
                            playlistId = pid
                        }
                    }
                }
            }
        }

        // Fallback: extract playlistId from microformat URL query parameter
        // URL format: https://music.youtube.com/playlist?list=OLAK5uy_...
        if playlistId == nil,
           let microformat = json["microformat"] as? [String: Any],
           let mfRenderer = microformat["microformatDataRenderer"] as? [String: Any],
           let urlCanonical = mfRenderer["urlCanonical"] as? String,
           let components = URLComponents(string: urlCanonical) {
            if let listParam = components.queryItems?.first(where: { $0.name == "list" })?.value {
                playlistId = listParam
            }
        }

        // --- Songs ---
        // Album track rows carry no per-row thumbnail; fall back to the album art (same as Metrolist).
        func parseSongsFromShelf(_ shelfDict: [String: Any], fallbackThumbnail: String?) -> [SongItem] {
            var result: [SongItem] = []
            let items: [[String: Any]]? =
                (shelfDict["musicPlaylistShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
                ?? (shelfDict["musicShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
            for itemDict in items ?? [] {
                if let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any],
                   var song = SongItem.from(renderer) {
                    if song.thumbnailUrl == nil { song.thumbnailUrl = fallbackThumbnail }
                    result.append(song)
                }
            }
            return result
        }

        if let twoCol = twoColumn {
            // Songs are in secondaryContents for two-column albums
            if let secondary = twoCol["secondaryContents"] as? [String: Any],
               let sectionList = secondary["sectionListRenderer"] as? [String: Any],
               let secondarySections = sectionList["contents"] as? [[String: Any]] {
                for section in secondarySections {
                    songs += parseSongsFromShelf(section, fallbackThumbnail: thumbnailUrl)
                }
            }
            // Fallback: songs might still be in first tab section (e.g. musicShelfRenderer)
            if songs.isEmpty, let firstSection = firstTabSection {
                songs += parseSongsFromShelf(firstSection, fallbackThumbnail: thumbnailUrl)
            }
        } else if let singleCol = singleColumn {
            if let tabs = singleCol["tabs"] as? [[String: Any]],
               let sections = tabs.first
                .flatMap({ $0["tabRenderer"] as? [String: Any] })
                .flatMap({ $0["content"] as? [String: Any] })
                .flatMap({ $0["sectionListRenderer"] as? [String: Any] })
                .flatMap({ $0["contents"] as? [[String: Any]] }) {
                for section in sections {
                    songs += parseSongsFromShelf(section, fallbackThumbnail: thumbnailUrl)
                }
            }
        }

        // Set songCount from actual count if header value wasn't parsed
        if songCount == 0 { songCount = songs.count }

        return AlbumDetailInfo(
            title: title,
            artists: artists,
            year: year,
            songCount: songCount,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            playlistId: playlistId,
            browseId: browseId,
            songs: songs
        )
    }
}

// MARK: - View

struct AlbumDetailView: View {
    let browseId: String
    @State private var viewModel: AlbumDetailViewModel

    @Environment(\.dismiss) private var dismiss

    init(browseId: String) {
        self.browseId = browseId
        _viewModel = State(initialValue: AlbumDetailViewModel(browseId: browseId))
    }

    var body: some View {
        ScrollView {
            Group {
                if viewModel.isLoading {
                    loadingView
                        .containerRelativeFrame(.vertical)
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "Couldn't load album",
                        systemImage: "exclamationmark.circle",
                        description: Text(error.localizedDescription)
                    )
                    .containerRelativeFrame(.vertical)
                } else if let album = viewModel.album {
                    albumContent(for: album)
                } else {
                    ContentUnavailableView(
                        "No album data",
                        systemImage: "music.note",
                        description: Text("Could not parse album details")
                    )
                    .containerRelativeFrame(.vertical)
                }
            }
        }
        .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.album == nil)
        .navigationTitle(viewModel.album?.title ?? "")
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
            Text("Loading album...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func albumContent(for album: AlbumDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: album)
                .padding(.bottom, 8)

            if album.songs.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Text("No songs found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                songList(for: album)
            }
        }
    }

    @ViewBuilder
    private func header(for album: AlbumDetailInfo) -> some View {
        VStack(spacing: 12) {
            // Album artwork
            AsyncImageView(url: album.thumbnailUrl)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)

            // Album title
            Text(album.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Clickable artist names
            if !album.artists.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(album.artists.enumerated()), id: \.offset) { i, artist in
                        if i > 0 {
                            Text(", ")
                                .foregroundColor(.secondary)
                        }
                        if let artistId = artist.id {
                            NavigationLink(value: DetailRoute.artist(browseId: artistId)) {
                                Text(artist.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(artist.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Metadata: year • song count • duration
            let metaParts = metaStrings(for: album)
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            // Action buttons: shuffle, play
            HStack(spacing: 20) {
                Button(action: { shufflePlay(album) }) {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)

                Button(action: { playAll(album) }) {
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
    private func songList(for album: AlbumDetailInfo) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(album.songs.enumerated()), id: \.offset) { index, song in
                Button(action: { playSong(song, in: album) }) {
                    HStack(spacing: 12) {
                        // Song thumbnail
                        AsyncImageView(url: song.thumbnailUrl)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Title and subtitle (artists • duration)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            let artistStr = song.artists.map(\.name).joined(separator: ", ")
                            let durationStr = song.duration.formattedDuration
                            let subtitleText = artistStr.isEmpty ? durationStr : (durationStr.isEmpty ? artistStr : "\(artistStr) • \(durationStr)")

                            Text(subtitleText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Options ellipsis
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if index < album.songs.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
    }

    // MARK: - Actions

    private func playAll(_ album: AlbumDetailInfo) {
        guard !album.songs.isEmpty else { return }
        let first = album.songs[0]
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
                print("[AlbumDetailView] Playing \(first.title) from album \(album.title)")
            } catch {
                print("[AlbumDetailView] Playback failed: \(error)")
            }
        }
    }

    private func shufflePlay(_ album: AlbumDetailInfo) {
        guard !album.songs.isEmpty else { return }
        let randomSong = album.songs.randomElement()!
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: randomSong.videoId)
                print("[AlbumDetailView] Shuffle playing \(randomSong.title) from album \(album.title)")
            } catch {
                print("[AlbumDetailView] Shuffle playback failed: \(error)")
            }
        }
    }

    private func playSong(_ song: SongItem, in album: AlbumDetailInfo) {
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
                print("[AlbumDetailView] Playing \(song.title)")
            } catch {
                print("[AlbumDetailView] Playback failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Builds metadata strings like "2024 • 12 songs • 45:30"
    private func metaStrings(for album: AlbumDetailInfo) -> [String] {
        var parts: [String] = []
        if let year = album.year { parts.append("\(year)") }
        if album.songCount > 0 { parts.append("\(album.songCount) song\(album.songCount != 1 ? "s" : "")") }
        if album.duration > 0 { parts.append(album.duration.formattedDuration) }
        return parts
    }
}

// MARK: - Detail Parsing Helpers

/// Namespaced helpers for parsing InnerTube browse page responses.
enum DetailParser {
    /// Extracts the first run text from a runs-based text dictionary.
    static func extractRunsText(_ dict: [String: Any]?) -> String? {
        guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
        return first["text"] as? String
    }

    /// Extracts the largest thumbnail URL from various InnerTube thumbnail formats.
    static func extractMusicThumbnail(_ dict: [String: Any]) -> String? {
        if let thumbnail = dict["thumbnail"] as? [String: Any],
           let musicThumb = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumb = musicThumb["thumbnail"] as? [String: Any],
           let thumbnails = thumb["thumbnails"] as? [[String: Any]],
           let last = thumbnails.last,
           let url = last["url"] as? String {
            return url
        }
        if let thumbnail = dict["thumbnail"] as? [String: Any],
           let thumb = thumbnail["thumbnails"] as? [[String: Any]],
           let last = thumb.last,
           let url = last["url"] as? String {
            return url
        }
        if let cropped = dict["croppedSquareThumbnail"] as? [String: Any],
           let thumb = cropped["thumbnails"] as? [[String: Any]],
           let last = thumb.last,
           let url = last["url"] as? String {
            return url
        }
        return nil
    }

    /// Parses a duration string like "3:45" or "1:02:30" into total seconds.
    static func parseDuration(_ text: String) -> Int {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ":.,")).compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return 0 }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}
