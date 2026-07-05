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

    init(playlistId: String) {
        self.playlistId = playlistId
    }

    /// Fetches playlist browse page from InnerTube and parses the response.
    /// Prependes "VL" to the playlistId if not already present (required by the browse endpoint).
    func load() async {
        print("[PlaylistDetailViewModel] Loading playlist playlistId=\(playlistId)")
        isLoading = true
        error = nil

        do {
            let browseId = playlistId.hasPrefix("VL") ? playlistId : "VL\(playlistId)"
            let json = try await innerTube.browse(browseId: browseId)
            print("[PlaylistDetailViewModel] Got browse response, parsing...")
            let parsed = Self.parsePlaylistDetail(from: json, playlistId: playlistId)
            playlist = parsed
            print("[PlaylistDetailViewModel] Parsed playlist: \(parsed.title), \(parsed.songs.count) songs")
            isLoading = false
        } catch {
            print("[PlaylistDetailViewModel] Failed: \(error)")
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

            if let strapline = detailHeader["straplineTextOne"] as? [String: Any],
               let runs = strapline["runs"] as? [[String: Any]] {
                if let firstRun = runs.first,
                   let text = firstRun["text"] as? String {
                    authorName = text
                    authorBrowseId = (firstRun["navigationEndpoint"] as? [String: Any])
                        .flatMap { $0["browseEndpoint"] as? [String: Any] }
                        .flatMap { $0["browseId"] as? String }
                }
            }
            if authorName == nil,
               let subtitle = detailHeader["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed == "•" { continue }
                    if let browse = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any],
                       let bid = browse["browseId"] as? String {
                        authorName = trimmed; authorBrowseId = bid; break
                    } else if authorName == nil {
                        authorName = trimmed
                    }
                }
            }

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
                        }
                    } else if trimmed.contains(":") {
                        duration = DetailParser.parseDuration(trimmed)
                    }
                }
            }
        }

        // Fallback: extract description from microformat
        if descriptionText == nil,
           let microformat = json["microformat"] as? [String: Any],
           let mfRenderer = microformat["microformatDataRenderer"] as? [String: Any],
           let desc = mfRenderer["description"] as? String {
            descriptionText = desc
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

        // Set songCount from actual count if header value wasn't parsed
        if songCount == 0 { songCount = songs.count }

        return PlaylistDetailInfo(
            title: title,
            authorName: authorName,
            authorBrowseId: authorBrowseId,
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
            AsyncImageView(url: playlist.thumbnailUrl)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)

            // Playlist title
            Text(playlist.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Clickable author name
            if let authorName = playlist.authorName {
                if let authorId = playlist.authorBrowseId {
                    NavigationLink(value: DetailRoute.artist(browseId: authorId)) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(authorName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(authorName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Metadata: song count • duration
            let metaParts = metaStrings(for: playlist)
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            // Description (truncated to 3 lines)
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
    private func songList(for playlist: PlaylistDetailInfo) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(playlist.songs.enumerated()), id: \.offset) { index, song in
                Button(action: { playSong(song, in: playlist) }) {
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
                print("[PlaylistDetailView] Playing \(first.title) from playlist \(playlist.title)")
            } catch {
                print("[PlaylistDetailView] Playback failed: \(error)")
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
                print("[PlaylistDetailView] Shuffle playing \(first.title) from playlist \(playlist.title)")
            } catch {
                print("[PlaylistDetailView] Shuffle playback failed: \(error)")
            }
        }
    }

    private func playSong(_ song: SongItem, in playlist: PlaylistDetailInfo) {
        guard let index = playlist.songs.firstIndex(where: { $0.videoId == song.videoId }) else { return }
        NowPlaying.shared.setQueue(playlist.songs, startIndex: index)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
                print("[PlaylistDetailView] Playing \(song.title)")
            } catch {
                print("[PlaylistDetailView] Playback failed: \(error)")
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
