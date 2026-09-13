//
//  BrowseLens.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation

/// Shared descents into InnerTube browse JSON. Consolidates the copy-pasted
/// `contents → singleColumnBrowseResultsRenderer → tabs[0] → tabRenderer →
/// content → sectionListRenderer` guard pyramids previously re-typed in every
/// parser. Lookup paths are preserved exactly — only the spine is unified,
/// leaf interpretation stays per call site.
enum BrowseLens {
    /// The `sectionListRenderer` dict of a browse response.
    static func sectionList(_ json: [String: Any]) -> [String: Any]? {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any] else { return nil }
        return sectionList
    }

    /// The section array of a browse response.
    static func browseSections(_ json: [String: Any]) -> [[String: Any]]? {
        guard let sectionList = sectionList(json),
              let sections = sectionList["contents"] as? [[String: Any]] else { return nil }
        return sections
    }

    /// The first section of a browse response.
    static func firstBrowseSection(_ json: [String: Any]) -> [String: Any]? {
        browseSections(json)?.first
    }

    /// First section's first item, tolerating single- and two-column
    /// layouts. Used by the album/podcast/playlist detail header parsers.
    static func firstSectionItem(_ json: [String: Any]) -> [String: Any]? {
        guard let contents = json["contents"] as? [String: Any] else { return nil }
        let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any]
        let tabsArray: [[String: Any]]? = {
            if let tabs = twoColumn?["tabs"] as? [[String: Any]] { return tabs }
            if let tabs = singleColumn?["tabs"] as? [[String: Any]] { return tabs }
            return nil
        }()
        return tabsArray?.first
            .flatMap { $0["tabRenderer"] as? [String: Any] }
            .flatMap { $0["content"] as? [String: Any] }
            .flatMap { $0["sectionListRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
    }

    /// Continuation token from a shelf's `continuations` array.
    static func continuationToken(in shelf: [String: Any]) -> String? {
        guard let continuations = shelf["continuations"] as? [[String: Any]],
              let first = continuations.first,
              let next = first["nextContinuationData"] as? [String: Any],
              let token = next["continuation"] as? String else { return nil }
        return token
    }

    /// Account-name runs from an `account/account_menu` response, used to
    /// probe session validity.
    static func accountNameRuns(_ json: [String: Any]) -> [[String: Any]]? {
        guard let header = json["header"] as? [String: Any],
              let renderer = header["musicAccountHeaderRenderer"] as? [String: Any],
              let accountName = renderer["accountName"] as? [String: Any],
              let runs = accountName["runs"] as? [[String: Any]] else { return nil }
        return runs
    }
}
