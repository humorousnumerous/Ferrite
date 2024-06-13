//
//  CloudTorrentView.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/6/24.
//

import SwiftUI

struct CloudTorrentView: View {
    @EnvironmentObject var navModel: NavigationViewModel
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var pluginManager: PluginManager

    @Store var debridSource: DebridSource

    @Binding var searchText: String

    var body: some View {
        DisclosureGroup("Torrents") {
            ForEach(debridSource.cloudTorrents.filter {
                searchText.isEmpty ? true : $0.fileName.lowercased().contains(searchText.lowercased())
            }, id: \.self) { cloudTorrent in
                Button {
                    if cloudTorrent.status == "downloaded", !cloudTorrent.links.isEmpty {
                        navModel.resultFromCloud = true
                        navModel.selectedTitle = cloudTorrent.fileName

                        var historyInfo = HistoryEntryJson(
                            name: cloudTorrent.fileName,
                            source: debridSource.id
                        )

                        Task {
                            let magnet = Magnet(hash: cloudTorrent.hash, link: nil)
                            await debridManager.populateDebridIA([magnet])
                            if debridManager.selectDebridResult(magnet: magnet) {
                                // Is this a batch?

                                if cloudTorrent.links.count == 1 {
                                    await debridManager.fetchDebridDownload(magnet: magnet)

                                    // Bump to batch
                                    if debridManager.requiresUnrestrict {
                                        navModel.selectedHistoryInfo = historyInfo
                                        navModel.currentChoiceSheet = .batch

                                        return
                                    }

                                    if !debridManager.downloadUrl.isEmpty {
                                        historyInfo.url = debridManager.downloadUrl
                                        PersistenceController.shared.createHistory(historyInfo, performSave: true)

                                        pluginManager.runDefaultAction(
                                            urlString: debridManager.downloadUrl,
                                            navModel: navModel
                                        )
                                    }
                                } else {
                                    navModel.selectedMagnet = magnet
                                    navModel.selectedHistoryInfo = historyInfo
                                    navModel.currentChoiceSheet = .batch
                                }
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(cloudTorrent.fileName)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)

                        HStack {
                            Text(cloudTorrent.status.capitalizingFirstLetter())
                            Spacer()
                            DebridLabelView(debridSource: debridSource, cloudLinks: cloudTorrent.links)
                        }
                        .font(.caption)
                    }
                }
                .disabledAppearance(navModel.currentChoiceSheet != nil, dimmedOpacity: 0.7, animation: .easeOut(duration: 0.2))
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    if let cloudTorrent = debridSource.cloudTorrents[safe: index] {
                        Task {
                            await debridManager.deleteCloudTorrent(cloudTorrent)
                        }
                    }
                }
            }
        }
    }
}
