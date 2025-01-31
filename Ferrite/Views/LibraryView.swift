//
//  LibraryView.swift
//  Ferrite
//
//  Created by Brian Dashore on 9/2/22.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var navModel: NavigationViewModel

    @FetchRequest(
        entity: Bookmark.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Bookmark.orderNum, ascending: true)]
    ) var bookmarks: FetchedResults<Bookmark>

    @FetchRequest(
        entity: HistoryEntry.entity(),
        sortDescriptors: []
    ) var allHistoryEntries: FetchedResults<HistoryEntry>

    @AppStorage("Behavior.AutocorrectSearch") var autocorrectSearch = true

    @State private var editMode: EditMode = .inactive

    // Bound to the isSearching environment var
    @State private var isSearching = false
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                switch navModel.libraryPickerSelection {
                case .bookmarks:
                    BookmarksView(searchText: $searchText, bookmarks: bookmarks)
                case .history:
                    HistoryView(allHistoryEntries: allHistoryEntries, searchText: $searchText)
                case .debridCloud:
                    if let selectedDebridSource = debridManager.selectedDebridSource {
                        DebridCloudView(debridSource: selectedDebridSource, searchText: $searchText)
                    } else {
                        // Placeholder view that takes up the entire parent view
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .overlay {
                if !isSearching {
                    switch navModel.libraryPickerSelection {
                    case .bookmarks:
                        if bookmarks.isEmpty {
                            EmptyInstructionView(title: "No Bookmarks", message: "Add a bookmark from search results")
                        }
                    case .history:
                        if allHistoryEntries.isEmpty {
                            EmptyInstructionView(title: "No History", message: "Start watching to build history")
                        }
                    case .debridCloud:
                        if debridManager.selectedDebridSource == nil {
                            EmptyInstructionView(title: "Cloud Unavailable", message: "Listing is not available for this service")
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Spacer()
                        EditButton()

                        switch navModel.libraryPickerSelection {
                        case .bookmarks, .debridCloud:
                            SelectedDebridFilterView {
                                Text(debridManager.selectedDebridSource?.abbreviation ?? "Debrid")
                            }
                            .transaction {
                                $0.animation = .none
                            }
                        case .history:
                            HistoryActionsView()
                        }
                    }
                }
            }
            .expandedSearchable(
                text: $searchText,
                scopeBarContent: {
                    LibraryPickerView()
                }
            )
            .autocorrectionDisabled(!autocorrectSearch)
            .esAutocapitalization(autocorrectSearch ? .sentences : .none)
            .environment(\.editMode, $editMode)
        }
        .alert("Not implemented", isPresented: $debridManager.showNotImplementedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(debridManager.notImplementedMessage)
        }
        .onChange(of: navModel.libraryPickerSelection) { _ in
            editMode = .inactive
        }
        .onDisappear {
            editMode = .inactive
        }
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}
