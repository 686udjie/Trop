//
//  HomeViewModel.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var homePage: HomePage?
    var homeSections: [HomeSection] = []
    var isLoading = true
    var isRefreshing = false
    var selectedChip: HomePage.Chip?
    var error: Error?

    var isLoggedIn = false
    var accountName = "Guest"
    var accountImageUrl: String?

    var isLoginSheetPresented = false
    var isAccountSheetPresented = false

    var hideExplicit = false {
        didSet { mergeSections() }
    }

    private var isHomeDataLoaded = false
    private var isLoadingMore = false
    private var loadGeneration = 0
    private var previousHomePage: HomePage?
    private let cookieStore = CookieStore()
    private let personalization = PersonalizationService.shared

    private var cachedLocalSections: [HomeSection] = []
    private var cachedPhase2Sections: [HomeSection] = []

    private var notificationObserver: NSObjectProtocol?

    init() {
        hideExplicit = SettingsStore.shared.hideExplicit
        if let existing = notificationObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .personalizationDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLocalSections()
        }
    }

    private nonisolated func refreshLocalSections() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let settings = SettingsStore.shared
            async let qp: HomeSection = settings.showQuickPicks
                ? await personalization.buildQuickPicks(limit: settings.topListsLength)
                : .quickPicks(items: [])
            async let kl: HomeSection = await personalization.buildKeepListening()
            async let ff: HomeSection = await personalization.buildForgottenFavorites()
            let (qpResult, klResult, ffResult) = await (qp, kl, ff)
            var local: [HomeSection] = []
            if !qpResult.items.isEmpty { local.append(qpResult) }
            if !klResult.items.isEmpty { local.append(klResult) }
            if !ffResult.items.isEmpty { local.append(ffResult) }
            self.cachedLocalSections = local
            self.mergeSections()
            await self.personalization.drainEnrichments()
            let refreshed = await (
                self.personalization.buildForgottenFavorites(),
                self.personalization.buildKeepListening()
            )
            var merged = local
            merged.removeAll { section in
                switch section {
                case .forgottenFavorites, .keepListening: return true
                default: return false
                }
            }
            if !refreshed.0.items.isEmpty { merged.append(refreshed.0) }
            if !refreshed.1.items.isEmpty { merged.append(refreshed.1) }
            self.cachedLocalSections = merged
            self.mergeSections()
        }
    }

    /// Re-reads settings that affect the feed (explicit filter, quick picks).
    func syncSettings() {
        let settings = SettingsStore.shared
        hideExplicit = settings.hideExplicit
    }

    func loadHomeData() {
        guard !isHomeDataLoaded else { return }
        isHomeDataLoaded = true
        Task { await load() }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            cachedLocalSections = []
            cachedPhase2Sections = []
            await load()
            isRefreshing = false
        }
    }

    func restoreSession() async {
        let loggedIn = await cookieStore.isLoggedIn()
        guard loggedIn else { return }
        isLoggedIn = true
        await InnerTube.shared.loadState(from: cookieStore)
        await fetchAccountInfo()
    }

    func handleLogin(cookies: [String: String], sapisid: String?, visitorData: String?) {
        isLoggedIn = sapisid != nil
        isLoginSheetPresented = false
        Task {
            await cookieStore.save(cookies: cookies, sapisid: sapisid, visitorData: visitorData)
            await InnerTube.shared.loadState(from: cookieStore)
            if isLoggedIn {
                await fetchAccountInfo()
                await loadPhase2Sections()
            }
        }
    }

    func logout() {
        Task {
            await cookieStore.clear()
            isLoggedIn = false
            accountName = "Guest"
            accountImageUrl = nil
            isAccountSheetPresented = false
            cachedPhase2Sections = []
            mergeSections()
        }
    }

    func tapAccount() {
        isAccountSheetPresented = true
    }

    private func fetchAccountInfo() async {
        do {
            let info = try await InnerTube.shared.accountInfo()
            accountName = info.name
            accountImageUrl = info.thumbnailUrl
        } catch {
            Log.homeViewModel.error("Failed to fetch account info: \(error)")
        }
    }

    // MARK: - Home Data Loading

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil

        async let localTask: Void = storeLocalSections()
        _ = await localTask
        guard generation == loadGeneration else { return }
        await personalization.drainEnrichments()
        mergeSections()
        isLoading = false

        Task { [generation] in
            await fetchHomePage(generation: generation)
            guard generation == self.loadGeneration else { return }
            await self.ensureQuickPicksAvailable(generation: generation)
            self.mergeSections()
        }

        Task { await loadPhase2Sections() }
    }

    private func ensureQuickPicksAvailable(generation: Int) async {
        guard SettingsStore.shared.showQuickPicks else { return }
        var attempts = 0
        while attempts < 3,
              generation == loadGeneration,
              !hasQuickPicksServerSection(),
              !isLoadingMore,
              let continuation = homePage?.continuation {
            attempts += 1
            isLoadingMore = true
            defer { isLoadingMore = false }
            do {
                let json = try await InnerTube.shared.browse(continuation: continuation)
                guard let (newSections, next) = HomePageParser.parseContinuationSections(from: json) else { break }
                homePage?.sections.append(contentsOf: newSections)
                homePage?.continuation = next
                mergeSections()
            } catch {
                break
            }
        }
    }

    private func hasQuickPicksServerSection() -> Bool {
        homePage?.sections.contains { section in
            if case .quickPicks = mapServerSection(section, index: 0) { return true }
            return false
        } ?? false
    }

    private func fetchHomePage(generation: Int) async {
        do {
            let json = try await InnerTube.shared.browse(browseId: "FEmusic_home")
            guard let page = HomePageParser.parseHomePage(from: json) else {
                if generation == loadGeneration {
                    error = InnerTubeError.decodingFailed
                }
                return
            }
            homePage = page
        } catch {
            if generation == loadGeneration {
                self.error = error
            }
        }
    }

    private func storeLocalSections() async {
        let settings = SettingsStore.shared
        async let qp: HomeSection = settings.showQuickPicks
            ? personalization.buildQuickPicks(limit: settings.topListsLength)
            : .quickPicks(items: [])
        async let kl: HomeSection = personalization.buildKeepListening()
        async let ff: HomeSection = personalization.buildForgottenFavorites()

        let (qpResult, klResult, ffResult) = await (qp, kl, ff)

        var local: [HomeSection] = []
        if !qpResult.items.isEmpty { local.append(qpResult) }
        if !klResult.items.isEmpty { local.append(klResult) }
        if !ffResult.items.isEmpty { local.append(ffResult) }
        cachedLocalSections = local
    }

    private func loadPhase2Sections() async {
        guard isLoggedIn else { return }

        async let ap: HomeSection = personalization.buildAccountPlaylists()
        async let dd: HomeSection = personalization.buildDailyDiscover()
        async let ct: HomeSection = personalization.buildFromTheCommunity()
        async let sr: [HomeSection] = personalization.buildSimilarRecommendations()

        let (apResult, ddResult, ctResult, srResults) = await (ap, dd, ct, sr)
        var phase2: [HomeSection] = []
        if !apResult.items.isEmpty { phase2.append(apResult) }
        if !ddResult.items.isEmpty { phase2.append(ddResult) }
        if !ctResult.items.isEmpty { phase2.append(ctResult) }
        phase2.append(contentsOf: srResults)
        cachedPhase2Sections = phase2

        mergeSections()
    }

    func toggleChip(_ chip: HomePage.Chip?) {
        if chip == nil || chip?.title == selectedChip?.title {
            homePage = previousHomePage
            previousHomePage = nil
            selectedChip = nil
            mergeSections()
            return
        }

        if selectedChip == nil {
            previousHomePage = homePage
        }

        selectedChip = chip
        Task {
            do {
                let json = try await InnerTube.shared.browse(
                    browseId: "FEmusic_home",
                    params: chip?.params
                )
                if let page = HomePageParser.parseHomePage(from: json) {
                    homePage?.sections = page.sections
                    mergeSections()
                }
            } catch {
                homePage = previousHomePage
                previousHomePage = nil
                selectedChip = nil
                mergeSections()
            }
        }
    }

    func loadMoreIfNeeded(currentIndex: Int, total: Int) {
        guard total - currentIndex <= 3,
              let continuation = homePage?.continuation,
              !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do {
                let json = try await InnerTube.shared.browse(continuation: continuation)
                if let (newSections, newContinuation) = HomePageParser.parseContinuationSections(from: json) {
                    homePage?.sections.append(contentsOf: newSections)
                    homePage?.continuation = newContinuation
                    mergeSections()
                }
            } catch {
                Log.homeViewModel.error("Continuation error: \(error)")
            }
        }
    }

    // MARK: - Section Management

    private func mergeSections() {
        let serverSections = homePage?.sections.enumerated().map { mapServerSection($1, index: $0) } ?? []
        let all = cachedLocalSections + serverSections + cachedPhase2Sections
        let merged = orderSections(all)
        homeSections = merged
    }

    private func mapServerSection(_ section: HomePage.Section, index: Int) -> HomeSection {
        let title = section.title.lowercased()
        if title == "quick picks" || title.contains("quick pick") {
            if !SettingsStore.shared.showQuickPicks {
                return .quickPicks(items: [])
            }
            return .quickPicks(items: section.items)
        }
        if title.contains("listen again") || title.contains("keep listening") {
            return .keepListening(items: section.items)
        }
        if title.contains("forgotten") || title.contains("favorite") {
            return .forgottenFavorites(items: section.items)
        }
        return .homePageSection(section, index: index)
    }

    private func orderSections(_ sections: [HomeSection]) -> [HomeSection] {
        let filtered = sections.compactMap { section -> HomeSection? in
            let f = applyFilters(section)
            if case .homePageSection = f { return f }
            return f.items.isEmpty ? nil : f
        }

        var byId: [String: HomeSection] = [:]
        for section in filtered {
            if let existing = byId[section.id] {
                if section.items.count > existing.items.count {
                    byId[section.id] = section
                }
            } else {
                byId[section.id] = section
            }
        }

        return byId.values.sorted { a, b in
            sectionWeight(a) > sectionWeight(b)
        }
    }

    private func applyFilters(_ section: HomeSection) -> HomeSection {
        let filteredItems = section.items.filter { item in
            if hideExplicit {
                switch item {
                case .song(let s) where s.isExplicit: return false
                case .album(let a) where a.isExplicit: return false
                default: break
                }
            }
            return true
        }

        switch section {
        case .quickPicks: return .quickPicks(items: filteredItems)
        case .keepListening: return .keepListening(items: filteredItems)
        case .forgottenFavorites: return .forgottenFavorites(items: filteredItems)
        case .homePageSection(let s, let i): return .homePageSection(s, index: i)
        case .accountPlaylists: return .accountPlaylists(items: filteredItems)
        case .similarRecommendation(_, let t): return .similarRecommendation(items: filteredItems, title: t)
        case .dailyDiscover: return .dailyDiscover(items: filteredItems)
        case .fromTheCommunity: return .fromTheCommunity(items: filteredItems)
        case .speedDial: return .speedDial(items: filteredItems)
        case .moodAndGenres: return .moodAndGenres(items: filteredItems)
        }
    }

    private func sectionWeight(_ section: HomeSection) -> Int {
        switch section {
        case .quickPicks: return 100
        case .keepListening: return 80
        case .forgottenFavorites: return 60
        case .homePageSection(_, let index): return 40 - index
        case .dailyDiscover: return 50
        case .similarRecommendation: return 35
        case .accountPlaylists: return 30
        case .fromTheCommunity: return 25
        case .speedDial: return 20
        case .moodAndGenres: return 15
        }
    }
}
