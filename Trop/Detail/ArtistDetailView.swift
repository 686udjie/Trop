//
//  ArtistDetailView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Nuke
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
            Self.preloadHeroArtwork(for: parsed.thumbnailUrl)
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
                name = InnerTubeJSON.runsText(immersive["title"] as? [String: Any]) ?? "Unknown Artist"
                thumbnailUrl = InnerTubeJSON.musicThumbnailURL(immersive)
                let subscription = extractSubscriptionDetails(from: immersive)
                isSubscribed = subscription.isSubscribed ?? false
                subscriberCountText = subscription.subscriberCountText
            } else if let responsive = header["musicResponsiveHeaderRenderer"] as? [String: Any] {
                name = InnerTubeJSON.runsText(responsive["title"] as? [String: Any]) ?? "Unknown Artist"
                thumbnailUrl = InnerTubeJSON.musicThumbnailURL(responsive)
                let subscription = extractSubscriptionDetails(from: responsive)
                isSubscribed = subscription.isSubscribed ?? false
                subscriberCountText = subscription.subscriberCountText
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
        if let sections = BrowseLens.browseSections(json) {

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

    /// Warms Nuke's cache before the artist screen appears, avoiding a second
    /// visible loading state for the immersive header artwork.
    private static func preloadHeroArtwork(for thumbnailUrl: String?) {
        guard let artworkURL = ArtworkURLs.sized(thumbnailUrl, width: 1200, height: 1200),
              let url = URL(string: artworkURL) else {
            return
        }

        ArtworkLoader.warm(url)
    }

    /// YouTube Music subscription payloads vary: the subscribed state is in `subscriptionButton`, 
    /// the count in `subscriptionButton2`, and older responses include a notification toggle.
    private static func extractSubscriptionDetails(
        from header: [String: Any]
    ) -> (isSubscribed: Bool?, subscriberCountText: String?) {
        var isSubscribed: Bool?
        var subscriberCountText: String?

        let buttons = ["subscriptionButton2", "subscriptionButton"]
            .compactMap { header[$0] as? [String: Any] }

        for button in buttons {
            if let subscribe = button["subscribeButtonRenderer"] as? [String: Any] {
                if isSubscribed == nil {
                    isSubscribed = subscribe["subscribed"] as? Bool
                }

                if subscriberCountText == nil {
                    for key in ["subscriberCountWithSubscribeText", "longSubscriberCountText", "shortSubscriberCountText"] {
                        if let count = InnerTubeJSON.runsText(subscribe[key] as? [String: Any]), !count.isEmpty {
                            subscriberCountText = count
                            break
                        }
                    }
                }
            }

            if let toggle = button["subscriptionNotificationToggleButtonRenderer"] as? [String: Any] {
                if isSubscribed == nil {
                    isSubscribed = toggle["subscribed"] as? Bool
                }
                if subscriberCountText == nil,
                   let count = InnerTubeJSON.runsText(toggle["subscribedText"] as? [String: Any]),
                   !count.isEmpty {
                    subscriberCountText = count
                }
            }
        }

        return (isSubscribed, subscriberCountText)
    }

    /// Extracts the title from a musicCarouselShelfBasicHeaderRenderer.
    private static func extractCarouselTitle(_ carousel: [String: Any]) -> String {
        guard let header = carousel["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let title = InnerTubeJSON.runsText(basicHeader["title"] as? [String: Any]) else {
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var scrollOffset: CGFloat = 0

    private static let barFadeStart: CGFloat = 80
    private static let barFadeDistance: CGFloat = 120

    private var barProgress: CGFloat {
        min(max((scrollOffset - Self.barFadeStart) / Self.barFadeDistance, 0), 1)
    }

    init(browseId: String) {
        self.browseId = browseId
        _viewModel = State(initialValue: ArtistDetailViewModel(browseId: browseId))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                DetailStateContainer(
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    data: viewModel.artist,
                    noun: "artist",
                    emptyIcon: "music.mic"
                ) { artist in
                    artistContent(for: artist)
                }
            }
            .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.artist == nil)
            .miniPlayerTracksScroll()
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: { $0.contentOffset.y },
                action: { _, newOffset in
                    scrollOffset = newOffset
                }
            )
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard viewModel.isLoading else { return }
                await viewModel.load()
            }

            customTopBar
        }
    }

    private var customTopBar: some View {
        HStack(spacing: 8) {
            topBarBackButton

            if let artist = viewModel.artist {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(barProgress)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color(.systemBackground)
                .opacity(barProgress)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(barProgress)
        }
    }

    private var topBarBackButton: some View {
        Button(action: { dismiss() }, label: {
            ZStack {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .opacity(1 - barProgress)
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .opacity(barProgress)
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private func artistContent(for artist: ArtistDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: artist)

            if !artist.songs.isEmpty {
                songsSection(songs: artist.songs)
            }

            if !artist.albums.isEmpty {
                albumsSection(albums: artist.albums)
            }

            if let description = artist.descriptionText, !description.isEmpty {
                aboutSection(description: description)
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
        if horizontalSizeClass == .regular {
            GeometryReader { proxy in
                headerBanner(
                    for: artist,
                    size: CGSize(width: proxy.size.width, height: Self.iPadBannerHeight)
                )
            }
            .frame(height: Self.iPadBannerHeight)
            .accessibilityElement(children: .contain)
        } else {
            // iPhone: full-width square banner.
            GeometryReader { proxy in
                headerBanner(for: artist, size: proxy.size)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .contain)
        }
    }

    private static let iPadBannerHeight: CGFloat = 400

    private func headerBanner(for artist: ArtistDetailInfo, size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(.systemGray5)

            AsyncImageView(
                url: ArtworkURLs.sized(artist.thumbnailUrl, width: 1200, height: 1200),
                contentMode: .fill
            )
            .frame(width: size.width, height: size.height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                Text(artist.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

                HStack(spacing: 12) {
                    Button(action: { toggleSubscribe(artist) }, label: {
                        Text(artist.isSubscribed ? "Subscribed" : "Subscribe")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(artist.isSubscribed ? Color.white : Color.black)
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .background(
                                Capsule()
                                    .fill(artist.isSubscribed ? Color.clear : Color.white)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(.white, lineWidth: artist.isSubscribed ? 1.5 : 0)
                            )
                    })
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    if let subText = artist.subscriberCountText, !subText.isEmpty {
                        Text(subscriberLabel(for: subText))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }

                    Button(action: { shufflePlay(artist) }, label: {
                        Image(systemName: "shuffle")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.accentColor))
                    })
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle artist")
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)
            .padding(.bottom, 24)
        }
    }

    private func subscriberLabel(for count: String) -> String {
        count.localizedCaseInsensitiveContains("subscriber") ? count : "\(count) subscribers"
    }

    @ViewBuilder
    private func aboutSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 16)

            Text(description)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(5)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func songsSection(songs: [SongItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Songs")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 20)

            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                                Button(action: { playSong(song) }, label: {
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
                    .padding(.vertical, 6)
                })
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
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            // Horizontal album carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(albums.indices, id: \.self) { i in
                        let album = albums[i]
                        NavigationLink(value: DetailRoute.album(browseId: album.browseId)) {
                            MediaGridCell(
                                thumbnailUrl: album.thumbnailUrl,
                                title: album.title,
                                subtitle: album.artists.map(\.name).joined(separator: ", "),
                                size: 156
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func shufflePlay(_ artist: ArtistDetailInfo) {
        PlaybackQueue.playShuffled(artist.songs, log: Log.artistDetail, context: "Shuffle playback")
    }

    private func playSong(_ song: SongItem) {
        guard let artist = viewModel.artist else { return }
        PlaybackQueue.play(song, in: artist.songs, log: Log.artistDetail, context: "Playback")
    }

    private func toggleSubscribe(_ artist: ArtistDetailInfo) {
        loggedTask(Log.artistDetail, "Subscribe failed") {
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
        }
    }
}
