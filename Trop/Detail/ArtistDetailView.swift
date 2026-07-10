//
//  ArtistDetailView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

// MARK: - View Model

@MainActor
@Observable
final class ArtistDetailViewModel {
    let browseId: String
    var artist: ArtistDetailInfo?
    var isLoading = true
    var error: Error?

    private let innerTube = InnerTube.shared

    init(browseId: String) {
        self.browseId = browseId
    }

    /// Fetches artist browse page from InnerTube and parses the response.
    func load() async {
        isLoading = true
        error = nil

        do {
            let json = try await innerTube.browse(browseId: browseId)
            let parsed = Self.parseArtistDetail(from: json, browseId: browseId)
            artist = parsed
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Parser

extension ArtistDetailViewModel {
    /// Parses InnerTube browse JSON into an ArtistDetailInfo.
    /// Handles both musicImmersiveHeaderRenderer and musicResponsiveHeaderRenderer for the header,
    /// then extracts songs from musicShelfRenderer and albums from musicCarouselShelfRenderer.
    static func parseArtistDetail(from json: [String: Any], browseId: String) -> ArtistDetailInfo {
        var name = "Unknown Artist"
        var thumbnailUrl: String?
        var subscriberCountText: String?
        var descriptionText: String?
        var isSubscribed = false
        var songs: [SongItem] = []
        var albums: [AlbumItem] = []

        // --- Header ---
        // Artist pages can use either an immersive header (large background image)
        // or a responsive header (smaller, more compact).
        if let header = json["header"] as? [String: Any] {
            if let immersive = header["musicImmersiveHeaderRenderer"] as? [String: Any] {
                name = DetailParser.extractRunsText(immersive["title"] as? [String: Any]) ?? "Unknown Artist"
                thumbnailUrl = DetailParser.extractMusicThumbnail(immersive)

                // Subscription state and subscriber count
                if let subButton = immersive["subscriptionButton"] as? [String: Any],
                   let toggle = subButton["subscriptionNotificationToggleButtonRenderer"] as? [String: Any] {
                    isSubscribed = (toggle["subscribed"] as? Bool) ?? false
                    if let subText = toggle["subscribedText"] as? [String: Any],
                       let runs = subText["runs"] as? [[String: Any]] {
                        subscriberCountText = runs.compactMap { $0["text"] as? String }.joined()
                    }
                }
            } else if let responsive = header["musicResponsiveHeaderRenderer"] as? [String: Any] {
                name = DetailParser.extractRunsText(responsive["title"] as? [String: Any]) ?? "Unknown Artist"
                thumbnailUrl = DetailParser.extractMusicThumbnail(responsive)

                if let subButton = responsive["subscriptionButton"] as? [String: Any],
                   let toggle = subButton["subscriptionNotificationToggleButtonRenderer"] as? [String: Any] {
                    isSubscribed = (toggle["subscribed"] as? Bool) ?? false
                    if let subText = toggle["subscribedText"] as? [String: Any],
                       let runs = subText["runs"] as? [[String: Any]] {
                        subscriberCountText = runs.compactMap { $0["text"] as? String }.joined()
                    }
                }
            }
        }

        if name == "Unknown Artist" || thumbnailUrl == nil,
           let microformat = json["microformat"] as? [String: Any],
           let mfRenderer = microformat["microformatDataRenderer"] as? [String: Any] {
            if name == "Unknown Artist", let mfTitle = mfRenderer["title"] as? String {
                name = mfTitle
            }
            if thumbnailUrl == nil, let thumb = mfRenderer["thumbnail"] as? [String: Any],
               let thumbnails = thumb["thumbnails"] as? [[String: Any]],
               let last = thumbnails.last,
               let url = last["url"] as? String {
                thumbnailUrl = url
            }
            if descriptionText == nil, let desc = mfRenderer["description"] as? String {
                descriptionText = desc
            }
        }

        // --- Sections ---
        if let contents = json["contents"] as? [String: Any] {
            if let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any] {
                if let tabs = singleColumn["tabs"] as? [[String: Any]],
                   let firstTab = tabs.first,
                   let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
                   let content = tabRenderer["content"] as? [String: Any],
                   let sectionList = content["sectionListRenderer"] as? [String: Any],
                   let sections = sectionList["contents"] as? [[String: Any]] {

            for sectionDict in sections {
                // musicShelfRenderer typically contains a list of songs
                if let shelf = sectionDict["musicShelfRenderer"] as? [String: Any],
                   let items = shelf["contents"] as? [[String: Any]] {
                    for itemDict in items {
                        if let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any],
                           let song = SongItem.from(renderer) {
                            songs.append(song)
                        }
                    }
                }

                // musicCarouselShelfRenderer typically contains albums, singles, etc.
                if let carousel = sectionDict["musicCarouselShelfRenderer"] as? [String: Any],
                   let items = carousel["contents"] as? [[String: Any]] {
                    for itemDict in items {
                        if let twoRow = itemDict["musicTwoRowItemRenderer"] as? [String: Any] {
                            let pageType = HomePageParser.extractPageType(twoRow)
                            if pageType == "MUSIC_PAGE_TYPE_ALBUM" || pageType == "MUSIC_PAGE_TYPE_AUDIOBOOK" {
                                if let albumItem = AlbumItem.from(twoRow) {
                                    albums.append(albumItem)
                                }
                            }
                        }
                    }
                }
            }
                }
            }
        }

        return ArtistDetailInfo(
            name: name,
            thumbnailUrl: thumbnailUrl,
            subscriberCountText: subscriberCountText,
            descriptionText: descriptionText,
            isSubscribed: isSubscribed,
            browseId: browseId,
            songs: songs,
            albums: albums
        )
    }

    /// Extracts the title from a musicCarouselShelfBasicHeaderRenderer.
    private static func extractCarouselTitle(_ carousel: [String: Any]) -> String {
        guard let header = carousel["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let title = DetailParser.extractRunsText(basicHeader["title"] as? [String: Any]) else {
            return "Unknown"
        }
        return title
    }
}

// MARK: - View

struct ArtistDetailView: View {
    let browseId: String
    @State private var viewModel: ArtistDetailViewModel

    @Environment(\.dismiss) private var dismiss

    init(browseId: String) {
        self.browseId = browseId
        _viewModel = State(initialValue: ArtistDetailViewModel(browseId: browseId))
    }

    var body: some View {
        ScrollView {
            Group {
                if viewModel.isLoading {
                    loadingView
                        .containerRelativeFrame(.vertical)
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "Couldn't load artist",
                        systemImage: "exclamationmark.circle",
                        description: Text(error.localizedDescription)
                    )
                    .containerRelativeFrame(.vertical)
                } else if let artist = viewModel.artist {
                    artistContent(for: artist)
                } else {
                    ContentUnavailableView(
                        "No artist data",
                        systemImage: "music.mic",
                        description: Text("Could not parse artist details")
                    )
                    .containerRelativeFrame(.vertical)
                }
            }
        }
        .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.artist == nil)
        .navigationTitle(viewModel.artist?.name ?? "")
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
            Text("Loading artist...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func artistContent(for artist: ArtistDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: artist)
                .padding(.bottom, 12)

            // About section with subscriber count and description
            if let desc = artist.descriptionText, !desc.isEmpty {
                aboutSection(description: desc, subscriberCount: artist.subscriberCountText)
            } else if let sub = artist.subscriberCountText, !sub.isEmpty {
                aboutSection(description: nil, subscriberCount: sub)
            }

            if !artist.songs.isEmpty {
                songsSection(songs: artist.songs)
            }

            if !artist.albums.isEmpty {
                albumsSection(albums: artist.albums)
            }

            if artist.songs.isEmpty && artist.albums.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Text("No content found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func header(for artist: ArtistDetailInfo) -> some View {
        VStack(spacing: 12) {
            // Circular artist photo
            AsyncImageView(url: artist.thumbnailUrl)
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)

            // Artist name
            Text(artist.name)
                .font(.title)
                .fontWeight(.bold)

            // Subscribe button and subscriber count
            HStack(spacing: 12) {
                if let subText = artist.subscriberCountText {
                    Text(subText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button(action: { toggleSubscribe(artist) }) {
                    Text(artist.isSubscribed ? "Subscribed" : "Subscribe")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(artist.isSubscribed ? .primary : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(artist.isSubscribed ? Color(.systemGray5) : Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }

            // Action buttons: shuffle, play
            HStack(spacing: 20) {
                Button(action: { shufflePlay(artist) }) {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)

                Button(action: { playTopSong(artist) }) {
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
    private func aboutSection(description: String?, subscriberCount: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 16)

            if let subCount = subscriberCount {
                Text(subCount)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }

            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(5)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func songsSection(songs: [SongItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Songs")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                Button(action: { playSong(song) }) {
                    HStack(spacing: 12) {
                        AsyncImageView(url: song.thumbnailUrl)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(song.artists.map(\.name).joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(song.duration.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }

    @ViewBuilder
    private func albumsSection(albums: [AlbumItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Albums")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Horizontal album carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(albums.indices, id: \.self) { i in
                        let album = albums[i]
                        NavigationLink(value: DetailRoute.album(browseId: album.browseId)) {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImageView(url: album.thumbnailUrl)
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(album.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                if !album.artists.isEmpty {
                                    Text(album.artists.map(\.name).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func playTopSong(_ artist: ArtistDetailInfo) {
        guard let first = artist.songs.first else { return }
        NowPlaying.shared.setQueue(artist.songs, startIndex: 0)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
            } catch {
                print("[ArtistDetailView] Playback failed: \(error)")
            }
        }
    }

    private func shufflePlay(_ artist: ArtistDetailInfo) {
        guard !artist.songs.isEmpty else { return }
        let shuffled = artist.songs.shuffled()
        let first = shuffled[0]
        NowPlaying.shared.setQueue(shuffled, startIndex: 0)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
            } catch {
                print("[ArtistDetailView] Shuffle playback failed: \(error)")
            }
        }
    }

    private func playSong(_ song: SongItem) {
        guard let artist = viewModel.artist,
              let index = artist.songs.firstIndex(where: { $0.videoId == song.videoId }) else { return }
        NowPlaying.shared.setQueue(artist.songs, startIndex: index)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                print("[ArtistDetailView] Playback failed: \(error)")
            }
        }
    }

    private func toggleSubscribe(_ artist: ArtistDetailInfo) {
        Task {
            do {
                let channelId = artist.browseId
                let entity = ArtistEntity(
                    id: artist.browseId,
                    name: artist.name,
                    thumbnailUrl: artist.thumbnailUrl,
                    bookmarkedAt: artist.isSubscribed ? nil : Date(),
                    isPodcastChannel: false,
                    channelId: channelId
                )
                try await DatabaseService.shared.insertOrReplace(entity)

                if artist.isSubscribed {
                    try await MutationService.shared.unsubscribeArtist(channelId: channelId, artistId: artist.browseId)
                } else {
                    try await MutationService.shared.subscribeArtist(channelId: channelId, artistId: artist.browseId)
                }

                await MainActor.run {
                    if let current = viewModel.artist {
                        viewModel.artist = ArtistDetailInfo(
                            name: current.name,
                            thumbnailUrl: current.thumbnailUrl,
                            subscriberCountText: current.subscriberCountText,
                            descriptionText: current.descriptionText,
                            isSubscribed: !current.isSubscribed,
                            browseId: current.browseId,
                            songs: current.songs,
                            albums: current.albums
                        )
                    }
                }
            } catch {
                print("[ArtistDetailView] Subscribe failed: \(error)")
            }
        }
    }
}
