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

    private var isHomeDataLoaded = false
    private var isLoadingMore = false
    private var previousHomePage: HomePage?
    private let cookieStore = CookieStore()

    func loadHomeData() {
        guard !isHomeDataLoaded else { return }
        isHomeDataLoaded = true
        Task { await load() }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
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

        do {
            let json = try await InnerTube.shared.browse(browseId: "FEmusic_home")
            guard let page = HomePageParser.parseHomePage(from: json) else {
                error = InnerTubeError.decodingFailed
                isLoading = false
                return
            }
            homePage = page
            recomputeSections()
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    func toggleChip(_ chip: HomePage.Chip?) {
        if chip == nil || chip?.title == selectedChip?.title {
            homePage = previousHomePage
            previousHomePage = nil
            selectedChip = nil
            recomputeSections()
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
                    recomputeSections()
                }
            } catch {
                homePage = previousHomePage
                previousHomePage = nil
                selectedChip = nil
                recomputeSections()
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
                    recomputeSections()
                }
            } catch {
                print("[HomeViewModel] Continuation error: \(error)")
            }
        }
    }

    private func recomputeSections() {
        guard let page = homePage else {
            homeSections = []
            return
        }
        var sections: [HomeSection] = []
        for (index, section) in page.sections.enumerated() {
            let mapped = mapServerSection(section, index: index)
            sections.append(mapped)
        }
        homeSections = orderSections(sections)
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
        sections.sorted { a, b in
            let weightA = sectionWeight(a)
            let weightB = sectionWeight(b)
            return weightA > weightB
        }
    }

    private func sectionWeight(_ section: HomeSection) -> Int {
        switch section {
        case .quickPicks:
            return 100
        case .keepListening:
            return 80
        case .forgottenFavorites:
            return 60
        case .homePageSection(_, let index):
            return 40 - index
        default:
            return 0
        }
    }
}
