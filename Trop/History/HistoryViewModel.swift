//
//  HistoryViewModel.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import Foundation

enum HistorySource: String, CaseIterable, Sendable {
    case local = "Local"
    case remote = "Remote"
}

@MainActor
@Observable
final class HistoryView {
    var groupedEntries: [(title: String, entries: [DatabaseService.HistoryEntry])] = []
    var remoteSections: [(title: String, songs: [SongItem])] = []
    var source: HistorySource = .local
    var isLoading = true
    var isRemoteLoading = false
    var remoteError: Error?

    private let db = DatabaseService.shared

    func load() async {
        isLoading = true
        await loadLocal()
        isLoading = false
    }

    func loadLocal() async {
        do {
            let raw = try await db.fetchHistory(limit: 100)
            groupedEntries = Self.groupByDate(raw)
        } catch {
            print("[HistoryView] Failed to load local history: \(error)")
        }
    }

    func loadRemote() async {
        guard source == .remote else { return }
        isRemoteLoading = true
        remoteError = nil
        do {
            let json = try await InnerTube.shared.browse(browseId: "FEmusic_history")
            let sections = Self.parseRemoteHistory(from: json)
            remoteSections = sections
        } catch {
            print("[HistoryView] Failed to load remote history: \(error)")
            remoteError = error
        }
        isRemoteLoading = false
    }

    func switchSource(_ newSource: HistorySource) {
        guard newSource != source else { return }
        source = newSource
        if newSource == .remote && remoteSections.isEmpty {
            Task { await loadRemote() }
        }
    }

    // MARK: - Local group by date

    private static func groupByDate(_ entries: [DatabaseService.HistoryEntry]) -> [(String, [DatabaseService.HistoryEntry])] {
        let cal = Calendar.current
        let now = Date()

        let todayStart = cal.startOfDay(for: now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart)!

        var today: [DatabaseService.HistoryEntry] = []
        var yesterday: [DatabaseService.HistoryEntry] = []
        var thisWeek: [DatabaseService.HistoryEntry] = []
        var older: [String: [DatabaseService.HistoryEntry]] = [:]

        let thisWeekStart: Date = {
            let weekday = cal.component(.weekday, from: now)
            let daysFromSunday = weekday - 1
            return cal.date(byAdding: .day, value: -daysFromSunday, to: todayStart) ?? todayStart
        }()

        for entry in entries {
            let ts = entry.event.timestamp
            if ts >= todayStart {
                today.append(entry)
            } else if ts >= yesterdayStart {
                yesterday.append(entry)
            } else if ts >= thisWeekStart {
                thisWeek.append(entry)
            } else {
                let monthKey = monthDateFormatter.string(from: ts)
                older[monthKey, default: []].append(entry)
            }
        }

        var result: [(String, [DatabaseService.HistoryEntry])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        for key in older.keys.sorted(by: >) {
            result.append((key, older[key]!))
        }
        return result
    }

    func deleteEvents(_ events: [Event]) async {
        for event in events {
            _ = try? await db.delete(event)
        }
        await loadLocal()
    }

    private static let monthDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    // MARK: - Remote history parse

    private static func parseRemoteHistory(from json: [String: Any]) -> [(title: String, songs: [SongItem])] {
        guard let contents = json["contents"] as? [String: Any] else {
            print("[HistoryView] No 'contents' in response, keys: \(json.keys.sorted())")
            return []
        }
        guard let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any] else {
            print("[HistoryView] No singleColumnBrowseResultsRenderer, keys: \(contents.keys.sorted())")
            return []
        }
        guard let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let shelfList = sectionList["contents"] as? [[String: Any]] else {
            print("[HistoryView] Couldn't navigate to sectionListRenderer.contents")
            return []
        }

        var sections: [(title: String, songs: [SongItem])] = []

        for shelfDict in shelfList {
            guard let shelf = shelfDict["musicShelfRenderer"] as? [String: Any] else {
                print("[HistoryView] Skipping non-musicShelfRenderer: \(shelfDict.keys.sorted())")
                continue
            }

            let title = extractShelfTitle(shelf) ?? "Unknown"
            guard let items = shelf["contents"] as? [[String: Any]] else { continue }

            var songs: [SongItem] = []
            for itemDict in items {
                guard let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }
                if let song = SongItem.from(renderer) {
                    songs.append(song)
                }
            }

            if !songs.isEmpty {
                sections.append((title, songs))
            }
        }

        return sections
    }

    private static func extractShelfTitle(_ shelf: [String: Any]) -> String? {
        guard let titleDict = shelf["title"] as? [String: Any],
              let runs = titleDict["runs"] as? [[String: Any]],
              let first = runs.first,
              let text = first["text"] as? String else {
            return nil
        }
        return text
    }
}
