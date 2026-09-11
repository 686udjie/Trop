//
// ExploreView.swift
// Trop
//
// Created by 686udjie on 11/09/2026.
//

import SwiftUI

struct ExploreView: View {
    @State private var viewModel = ExploreViewModel()
    @ObservedObject private var router = AppRouter.shared

    @State private var pendingRoute: DetailRoute?

    @StateObject private var loginModel = LoginViewModel()
    @State private var isLoginSheetPresented = false
    @State private var isAccountSheetPresented = false
    @State private var accountName = "Guest"
    @State private var accountImageUrl: String?

    var body: some View {
        NavigationStack(path: $router.explorePath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Explore",
                    accountIsLoggedIn: loginModel.isLoggedIn,
                    accountImageUrl: accountImageUrl,
                    onHistory: { router.explorePath.append(DetailRoute.history) },
                    onAccount: { tapAccount() }
                )

                content
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .navigationDestination(for: MoodItem.self) { mood in
                MoodDetailView(mood: mood)
            }
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.explorePath.append(route)
                    pendingRoute = nil
                }
            }
            .onAppear { viewModel.load() }
            .sheet(isPresented: $isLoginSheetPresented) {
                NavigationStack {
                    LoginWebView(model: loginModel)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isLoginSheetPresented = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isAccountSheetPresented) {
                accountSheet
            }
            .onChange(of: loginModel.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    isLoginSheetPresented = false
                    Task { await fetchAccountInfo() }
                }
            }
            .task {
                loginModel.restoreSessionIfPresent()
                await fetchAccountInfo()
            }
            .task(id: viewModel.sections.count) {
                let urls = viewModel.sections
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            ExploreSkeletonView()
        case .loaded:
            sectionsList
        case .empty:
            ContentUnavailableView(
                "Nothing to explore",
                systemImage: "flame",
                description: Text("Try again later.")
            )
        case .failed:
            ContentUnavailableView(
                "Explore failed",
                systemImage: "exclamationmark.triangle",
                description: Text("Couldn't load Explore. Pull to retry.")
            )
        }
    }

    private var sectionsList: some View {
        ScrollView {
            ExploreSectionsList(sections: viewModel.sections, pendingRoute: $pendingRoute)
                .padding(.bottom, 16)
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Account

    private func tapAccount() {
        isAccountSheetPresented = true
    }

    private func fetchAccountInfo() async {
        guard loginModel.isLoggedIn else { return }
        do {
            let info = try await InnerTube.shared.accountInfo()
            accountName = info.name
            accountImageUrl = info.thumbnailUrl
        } catch {
            Log.explore.error("Failed to fetch account info: \(error)")
        }
    }

    private var accountSheet: some View {
        AccountSheetView(
            isLoggedIn: loginModel.isLoggedIn,
            titleText: accountName,
            accountImageUrl: accountImageUrl,
            onDone: { isAccountSheetPresented = false },
            onLogin: {
                isAccountSheetPresented = false
                DispatchQueue.main.async {
                    isLoginSheetPresented = true
                }
            },
            onSettings: {
                isAccountSheetPresented = false
                router.explorePath.append(DetailRoute.settings)
            },
            onSignOut: {
                loginModel.logout()
                accountName = "Guest"
                accountImageUrl = nil
                isAccountSheetPresented = false
            }
        )
    }
}

// MARK: - Shared section list

/// Renders Explore sections (song grids, card carousels, mood grids).
/// Shared by the Explore tab and mood category pages.
struct ExploreSectionsList: View {
    @ObservedObject private var router = AppRouter.shared
    var sections: [ExploreSection]
    var pendingRoute: Binding<DetailRoute?>

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(sections) { section in
                switch section.kind {
                case .rows:
                    songGrid(section)
                case .cards:
                    cardsCarousel(section)
                case .moods:
                    moodsGrid(section)
                }
            }
        }
        .onAppear {
            Log.explore.debug(
                "Render sections: " +
                sections.map { "\($0.title)(\($0.kind)):\($0.items.count)" }.joined(separator: ", ")
            )
        }
    }

    // MARK: - Rows

    /// Song rows in a 4-row grid scrolling horizontally.
    private func songGrid(_ section: ExploreSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationTitleView(title: section.title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0)
                    ],
                    spacing: 12
                ) {
                    ForEach(section.items, id: \.id) { item in
                        YouTubeListItemView(item: item, onTap: {
                            openItem(item)
                        }, onNavigate: { pendingRoute.wrappedValue = $0 })
                        .frame(width: 320, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Cards carousel

    private func cardsCarousel(_ section: ExploreSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationTitleView(title: section.title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(section.items, id: \.id) { item in
                        YouTubeGridItemView(item: item, onTap: {
                            openItem(item)
                        })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Moods grid

    private func moodsGrid(_ section: ExploreSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationTitleView(title: section.title)
            // Two-row grid scrolling horizontally: all 50+ moods reachable
            // without a dominating vertical wall.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(section.moods) { mood in
                        NavigationLink(value: mood) {
                            Text(mood.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 150)
                                .frame(minHeight: 64)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray5).opacity(0.6))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Navigation & playback

    private func openItem(_ item: YTItem) {
        switch item {
        case .song(let s):
            ExploreViewModel.playSong(s)
        case .album(let a):
            router.explorePath.append(DetailRoute.album(browseId: a.browseId))
        case .artist(let a):
            router.explorePath.append(DetailRoute.artist(browseId: a.browseId))
        case .playlist(let p):
            router.explorePath.append(DetailRoute.playlist(playlistId: p.id))
        case .episode(let e):
            ExploreViewModel.playSong(e.toSongItem())
        case .podcast(let p):
            router.explorePath.append(DetailRoute.podcast(browseId: p.browseId))
        }
    }
}

// MARK: - Mood detail

/// Full mood/genre category page: songs grid, playlists, videos, albums.
private struct MoodDetailView: View {
    let mood: MoodItem

    @State private var sections: [ExploreSection]?
    @State private var pendingRoute: DetailRoute?

    var body: some View {
        Group {
            if let sections {
                if sections.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "square.grid.2x2",
                        description: Text("Nothing found for \(mood.title).")
                    )
                } else {
                    ScrollView {
                        ExploreSectionsList(sections: sections, pendingRoute: $pendingRoute)
                            .padding(.bottom, 16)
                    }
                    .scrollIndicators(.automatic)
                    .miniPlayerTracksScroll()
                }
            } else {
                MoodDetailSkeletonView()
            }
        }
        .navigationTitle(mood.title)
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: pendingRoute) { _, route in
            if let route {
                AppRouter.shared.explorePath.append(route)
                pendingRoute = nil
            }
        }
        .task {
            sections = await ExploreViewModel.loadMoodDetail(mood)
        }
    }
}

// MARK: - Explore tab skeleton

/// Loading placeholder mirroring the Explore tab: album cards, the
/// 2-row moods grid, then a 4-row song grid.
private struct ExploreSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerBlock(width: 220, height: 22, radius: 6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 4) {
                                    ShimmerBlock(width: 160, height: 160, radius: 8)
                                    ShimmerBlock(width: 130, height: 14, radius: 4)
                                    ShimmerBlock(width: 90, height: 12, radius: 4)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerBlock(width: 160, height: 22, radius: 6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(
                            rows: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(0..<10, id: \.self) { _ in
                                ShimmerBlock(width: 150, height: 64, radius: 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerBlock(width: 120, height: 22, radius: 6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(
                            rows: [
                                GridItem(.flexible(), spacing: 0),
                                GridItem(.flexible(), spacing: 0),
                                GridItem(.flexible(), spacing: 0),
                                GridItem(.flexible(), spacing: 0)
                            ],
                            spacing: 12
                        ) {
                            ForEach(0..<12, id: \.self) { _ in
                                HStack(spacing: 12) {
                                    ShimmerBlock(width: 48, height: 48, radius: 4)
                                    VStack(alignment: .leading, spacing: 6) {
                                        ShimmerBlock(width: 180, height: 14, radius: 4)
                                        ShimmerBlock(width: 120, height: 12, radius: 4)
                                    }
                                    Spacer()
                                }
                                .frame(width: 320, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Mood detail skeleton

/// Loading placeholder mirroring the mood page layout: a vertical song
/// list followed by large playlist cards.
private struct MoodDetailSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerBlock(width: 80, height: 22, radius: 6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 12) {
                                ShimmerBlock(width: 48, height: 48, radius: 4)
                                VStack(alignment: .leading, spacing: 6) {
                                    ShimmerBlock(width: 190, height: 14, radius: 4)
                                    ShimmerBlock(width: 130, height: 12, radius: 4)
                                }
                                Spacer()
                                ShimmerBlock(width: 90, height: 20, radius: 4)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                }
                skeletonCardsSection(titleWidth: 200)
                skeletonCardsSection(titleWidth: 220)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func skeletonCardsSection(titleWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ShimmerBlock(width: titleWidth, height: 22, radius: 6)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 4) {
                            ShimmerBlock(width: 160, height: 160, radius: 8)
                            ShimmerBlock(width: 130, height: 14, radius: 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}
