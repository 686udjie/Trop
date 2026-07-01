//
//  HomeScreenView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct HomeScreenView: View {
    @State private var viewModel = HomeViewModel()
    @StateObject private var loginModel = LoginViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("Home")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    AccountButtonView(
                        isLoggedIn: viewModel.isLoggedIn,
                        accountImageUrl: viewModel.accountImageUrl,
                        onTap: { viewModel.tapAccount() }
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if viewModel.isLoading {
                    Spacer()
                    ShimmerLoadingView()
                    Spacer()
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    homescreenContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationBarHidden(true)
            .sheet(isPresented: $viewModel.isLoginSheetPresented) {
                NavigationStack {
                    LoginWebView(model: loginModel)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { viewModel.isLoginSheetPresented = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $viewModel.isAccountSheetPresented) {
                accountSheet
            }
            .onChange(of: loginModel.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    viewModel.isLoginSheetPresented = false
                    viewModel.handleLogin(
                        cookies: loginModel.cookies,
                        sapisid: loginModel.sapisid,
                        visitorData: loginModel.visitorData
                    )
                }
            }
            .onChange(of: viewModel.isLoginSheetPresented) { _, presented in
                if !presented {
                    loginModel.isPresented = false
                }
            }
            .task {
                await viewModel.restoreSession()
                viewModel.loadHomeData()
            }
        }
    }

    private var homescreenContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let chips = viewModel.homePage?.chips, !chips.isEmpty {
                    ChipsRowView(
                        chips: chips,
                        selectedChip: viewModel.selectedChip,
                        onChipTap: { viewModel.toggleChip($0) }
                    )
                }

                ForEach(viewModel.homeSections.indices, id: \.self) { index in
                    let section = viewModel.homeSections[index]
                    sectionView(for: section)
                }

                GeometryReader { _ in
                    Color.clear
                        .onAppear {
                            let total = viewModel.homeSections.count
                            if total > 0 {
                                viewModel.loadMoreIfNeeded(
                                    currentIndex: total - 1,
                                    total: total
                                )
                            }
                        }
                }
                .frame(height: 1)
            }
        }
        .scrollIndicators(.automatic)
        .refreshable {
            viewModel.refresh()
            await refreshTask()
        }
    }

    private var accountSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AccountButtonView(
                            isLoggedIn: viewModel.isLoggedIn,
                            accountImageUrl: viewModel.accountImageUrl,
                            onTap: {}
                        )
                        .scaleEffect(1.3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.accountName)
                                .font(.headline)
                            if viewModel.isLoggedIn {
                                Text("Signed in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Not signed in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if viewModel.isLoggedIn {
                    Section {
                        Button(role: .destructive) {
                            viewModel.logout()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { viewModel.isAccountSheetPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func refreshTask() async {
        while viewModel.isRefreshing {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .quickPicks:
            quickPicksSection(section)
        case .keepListening:
            mixedSection(section)
        case .forgottenFavorites:
            songsSection(section)
        case .homePageSection(let sectionData, _):
            if sectionData.isSongsOnly {
                songsSection(section)
            } else {
                mixedSection(section)
            }
        default:
            mixedSection(section)
        }
    }

    private func quickPicksSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        YouTubeListItemView(item: item, onTap: { playItem(item) })
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func songsSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        YouTubeListItemView(item: item, onTap: { playItem(item) })
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func mixedSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        YouTubeGridItemView(item: item, onTap: { playItem(item) })
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }

    private func playItem(_ item: YTItem) {
        guard let videoId = item.videoId else { return }
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
            } catch {
                print("[HomeScreenView] Playback failed: \(error)")
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "Couldn't load your homescreen",
            systemImage: "wifi.slash",
            description: Text(error.localizedDescription)
        )
    }
}

#Preview {
    HomeScreenView()
}
