//
//  NavigationViewModel.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/24/22.
//

import SwiftUI

@MainActor
class NavigationViewModel: ObservableObject {
    var logManager: LoggingManager?

    // Used between SearchResultsView and MagnetChoiceView
    enum ChoiceSheetType: Identifiable {
        var id: Int {
            hashValue
        }

        case action
        case batch
        case activity
    }

    enum ViewTab {
        case search
        case plugins
        case settings
        case library
    }

    enum LibraryPickerSegment {
        case bookmarks
        case history
        case debridCloud
    }

    enum PluginPickerSegment {
        case sources
        case actions
    }

    @Published var selectedMagnet: Magnet?
    @Published var selectedHistoryInfo: HistoryEntryJson?
    @Published var resultFromCloud: Bool = false

    // For giving information in magnet choice sheet
    @Published var selectedTitle: String = ""
    @Published var selectedBatchTitle: String = ""

    // For filters
    @Published var enabledFilters: Set<FilterType> = []
    @Published var currentSortFilter: SortFilter?
    @Published var currentSortOrder: SortOrder = .forward

    func compareSearchResult(lhs: SearchResult, rhs: SearchResult) -> Bool {
        switch currentSortFilter {
        case .leechers:
            guard let lhsLeechers = lhs.leechers, let rhsLeechers = rhs.leechers else {
                return false
            }

            return currentSortOrder == .forward ? lhsLeechers > rhsLeechers : lhsLeechers < rhsLeechers
        case .seeders:
            guard let lhsSeeders = lhs.seeders, let rhsSeeders = rhs.seeders else {
                return false
            }

            return currentSortOrder == .forward ? lhsSeeders > rhsSeeders : lhsSeeders < rhsSeeders
        case .size:
            guard let lhsSize = lhs.rawSize(), let rhsSize = rhs.rawSize() else {
                return false
            }

            return currentSortOrder == .forward ? lhsSize > rhsSize : lhsSize < rhsSize
        case .none:
            return false
        }
    }

    @Published var kodiExpanded: Bool = false

    @Published var currentChoiceSheet: ChoiceSheetType?
    var activityItems: [Any] = []

    // Used to show the activity sheet in the share menu
    @Published var showLocalActivitySheet = false

    @Published var selectedTab: ViewTab = .search

    // Used between service views and editor views in Settings
    @Published var selectedPluginList: PluginList?
    @Published var selectedKodiServer: KodiServer?

    @Published var libraryPickerSelection: LibraryPickerSegment = .bookmarks
    @Published var pluginPickerSelection: PluginPickerSegment = .sources

    @Published var searchPrompt: String = "Search"
    @Published var lastSearchPromptIndex: Int = -1
    private let searchBarTextArray: [String] = [
        "What's on your mind?",
        "Discover something interesting",
        "Find an engaging show",
        "Feeling adventurous?",
        "Look for something new",
        "The classics are a good idea"
    ]

    func getSearchPrompt() {
        if UserDefaults.standard.bool(forKey: "Behavior.UsesRandomSearchText") {
            let num = Int.random(in: 0 ..< searchBarTextArray.count - 1)
            if num == lastSearchPromptIndex {
                lastSearchPromptIndex = num + 1
                searchPrompt = searchBarTextArray[safe: num + 1] ?? "Search"
            } else {
                lastSearchPromptIndex = num
                searchPrompt = searchBarTextArray[safe: num] ?? "Search"
            }
        } else {
            lastSearchPromptIndex = -1
            searchPrompt = "Search"
        }
    }
}
