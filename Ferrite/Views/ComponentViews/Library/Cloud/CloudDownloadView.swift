//
//  CloudDownloadView.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/6/24.
//

import SwiftUI

struct CloudDownloadView: View {
    @EnvironmentObject var navModel: NavigationViewModel
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var pluginManager: PluginManager

    @Store var debridSource: DebridSource

    @Binding var searchText: String

    var body: some View {
        DisclosureGroup("Downloads") {
            ForEach(debridSource.cloudDownloads.filter {
                searchText.isEmpty ? true : $0.fileName.lowercased().contains(searchText.lowercased())
            }, id: \.self) { cloudDownload in
                Button(cloudDownload.fileName) {
                    navModel.resultFromCloud = true
                    navModel.selectedTitle = cloudDownload.fileName
                    var historyEntry = HistoryEntryJson(
                        name: cloudDownload.fileName,
                        source: debridSource.id
                    )

                    debridManager.currentDebridTask = Task {
                        await debridManager.fetchDebridDownload(magnet: nil, cloudInfo: cloudDownload.link)

                        if !debridManager.downloadUrl.isEmpty {
                            historyEntry.url = debridManager.downloadUrl
                            PersistenceController.shared.createHistory(historyEntry, performSave: true)

                            pluginManager.runDefaultAction(
                                urlString: debridManager.downloadUrl,
                                navModel: navModel
                            )
                        }
                    }
                }
                .disabledAppearance(navModel.currentChoiceSheet != nil, dimmedOpacity: 0.7, animation: .easeOut(duration: 0.2))
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    if let cloudDownload = debridSource.cloudDownloads[safe: index] {
                        Task {
                            await debridManager.deleteCloudDownload(cloudDownload)
                        }
                    }
                }
            }
        }
    }
}
