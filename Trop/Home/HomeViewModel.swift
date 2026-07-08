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
    private var previousHomePage: HomePage?
    private let cookieStore = CookieStore()
    private let personalization = PersonalizationService.shared

    private var cachedLocalSections: [HomeSection] = []
    private var cachedPhase2Sections: [HomeSection] = []

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
        if isLoggedIn {
            isAccountSheetPresented = true
        } else {
            isLoginSheetPresented = true
        }
    }

    private func fetchAccountInfo() async {
        do {
            let info = try await InnerTube.shared.accountInfo()
            accountName = info.name
            accountImageUrl = info.thumbnailUrl
        } catch {
            print("[HomeViewModel] Failed to fetch account info: \(error)")
        }
    }

    // MARK: - Home Data Loading

    private func load() async {
        isLoading = true
        error = nil

        async let serverTask: Void = loadServerSections()
        async let localTask: Void = loadLocalSections()

        _ = await (serverTask, localTask)

        isLoading = false

        Task { await loadPhase2Sections() }
    }

    private func loadServerSections() async {
        do {
            let json = try await InnerTube.shared.browse(browseId: "FEmusic_home")
            guard let page = HomePageParser.parseHomePage(from: json) else {
                error = InnerTubeError.decodingFailed
                return
            }
            homePage = page
            let serverSections = page.sections.enumerated().map { mapServerSection($1, index: $0) }
            let existingLocal = cachedLocalSections
            let existingPhase2 = cachedPhase2Sections
            homeSections = orderSections(existingLocal + serverSections + existingPhase2)
        } catch {
            self.error = error
        }
    }

    private func loadLocalSections() async {
        async let qp: HomeSection = personalization.buildQuickPicks()
        async let kl: HomeSection = personalization.buildKeepListening()
        async let ff: HomeSection = personalization.buildForgottenFavorites()

        let (qpResult, klResult, ffResult) = await (qp, kl, ff)

        var local: [HomeSection] = []
        if !qpResult.items.isEmpty { local.append(qpResult) }
        if !klResult.items.isEmpty { local.append(klResult) }
        if !ffResult.items.isEmpty { local.append(ffResult) }
        cachedLocalSections = local

        let serverSections = homePage?.sections.enumerated().map { mapServerSection($1, index: $0) } ?? []
        let existingPhase2 = cachedPhase2Sections
        homeSections = orderSections(local + serverSections + existingPhase2)
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
                print("[HomeViewModel] Continuation error: \(error)")
            }
        }
    }

    // MARK: - Section Management

    private func mergeSections() {
        let serverSections = homePage?.sections.enumerated().map { mapServerSection($1, index: $0) } ?? []
        let all = cachedLocalSections + serverSections + cachedPhase2Sections
        homeSections = orderSections(all)
    }

    private func mapServerSection(_ section: HomePage.Section, index: Int) -> HomeSection {
        let title = section.title.lowercased()
        if title == "quick picks" || title.contains("quick pick") {
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

        var seen = Set<String>()
        let deduped = filtered.filter { seen.insert($0.id).inserted }

        return deduped.sorted { a, b in
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
