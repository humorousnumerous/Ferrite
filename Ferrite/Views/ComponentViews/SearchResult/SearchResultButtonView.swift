//
//  SearchResultButtonView.swift
//  Ferrite
//
//  Created by Brian Dashore on 9/2/22.
//

import SwiftUI

struct SearchResultButtonView: View {
    let backgroundContext = PersistenceController.shared.backgroundContext

    @EnvironmentObject var navModel: NavigationViewModel
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var pluginManager: PluginManager

    var result: SearchResult
    var debridIAStatus: IAStatus?

    @State private var runOnce = false
    @State var existingBookmark: Bookmark? = nil
    @State private var showConfirmation = false

    var body: some View {
        Button {
            if debridManager.currentDebridTask == nil {
                navModel.selectedMagnet = result.magnet
                navModel.selectedTitle = result.title ?? ""
                navModel.resultFromCloud = false

                switch debridIAStatus ?? debridManager.matchMagnetHash(result.magnet) {
                case .full:
                    if debridManager.selectDebridResult(magnet: result.magnet) {
                        debridManager.currentDebridTask = Task {
                            await debridManager.fetchDebridDownload(magnet: result.magnet)

                            if !debridManager.downloadUrl.isEmpty {
                                PersistenceController.shared.createHistory(
                                    HistoryEntryJson(
                                        name: result.title,
                                        url: debridManager.downloadUrl,
                                        source: result.source
                                    ),
                                    performSave: true
                                )

                                pluginManager.runDefaultAction(
                                    urlString: debridManager.downloadUrl,
                                    navModel: navModel
                                )

                                if navModel.currentChoiceSheet != .action {
                                    debridManager.downloadUrl = ""
                                }
                            }
                        }
                    }
                case .partial:
                    if debridManager.selectDebridResult(magnet: result.magnet) {
                        navModel.selectedHistoryInfo = HistoryEntryJson(
                            name: result.title,
                            source: result.source
                        )
                        navModel.currentChoiceSheet = .batch
                    }
                case .none:
                    PersistenceController.shared.createHistory(
                        HistoryEntryJson(
                            name: result.title,
                            url: result.magnet.link,
                            source: result.source
                        ),
                        performSave: true
                    )

                    pluginManager.runDefaultAction(
                        urlString: result.magnet.link,
                        navModel: navModel
                    )
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(result.title ?? "No title")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)

                SearchResultInfoView(result: result)
            }
            .disabledAppearance(navModel.currentChoiceSheet != nil, dimmedOpacity: 0.7, animation: .easeOut(duration: 0.2))
        }
        .disableInteraction(navModel.currentChoiceSheet != nil)
        .tint(.primary)
        .conditionalContextMenu(id: existingBookmark) {
            ZStack {
                if let bookmark = existingBookmark {
                    Button {
                        PersistenceController.shared.delete(bookmark, context: backgroundContext)

                        // When the entity is deleted, let other instances know to remove that reference
                        NotificationCenter.default.post(name: .didDeleteBookmark, object: existingBookmark)
                    } label: {
                        Text("Remove bookmark")
                        Image(systemName: "bookmark.slash.fill")
                    }
                } else {
                    Button {
                        let newBookmark = Bookmark(context: backgroundContext)
                        newBookmark.title = result.title
                        newBookmark.source = result.source
                        newBookmark.magnetHash = result.magnet.hash
                        newBookmark.magnetLink = result.magnet.link
                        newBookmark.seeders = result.seeders
                        newBookmark.leechers = result.leechers

                        existingBookmark = newBookmark

                        PersistenceController.shared.save(backgroundContext)
                    } label: {
                        Text("Bookmark")
                        Image(systemName: "bookmark")
                    }
                }
            }
        }
        .alert("Caching file", isPresented: $debridManager.showDeleteAlert) {
            Button("Yes", role: .destructive) {
                Task {
                    try? await debridManager.selectedDebridSource?.deleteTorrent(torrentId: nil)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(String(describing: debridManager.selectedDebridSource?.id)) is currently caching this file. " +
                    "Would you like to delete it? \n\n" +
                    "Progress can be checked on the RealDebrid website."
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .didDeleteBookmark)) { notification in
            // If the instance contains the deleted bookmark, remove it.
            if let deletedBookmark = notification.object as? Bookmark,
               let bookmark = existingBookmark,
               deletedBookmark.objectID == bookmark.objectID
            {
                existingBookmark = nil
            }
        }
        .onAppear {
            // Only run a exists request if a bookmark isn't passed to the view
            if existingBookmark == nil, !runOnce {
                let bookmarkRequest = Bookmark.fetchRequest()
                bookmarkRequest.predicate = NSPredicate(
                    format: "title == %@ AND source == %@ AND magnetLink == %@ AND magnetHash = %@",
                    result.title ?? "",
                    result.source,
                    result.magnet.link ?? "",
                    result.magnet.hash ?? ""
                )
                bookmarkRequest.fetchLimit = 1

                if let fetchedBookmark = try? backgroundContext.fetch(bookmarkRequest).first {
                    existingBookmark = fetchedBookmark
                }

                runOnce = true
            }
        }
    }
}
