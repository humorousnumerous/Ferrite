//
//  RealDebridCloudView.swift
//  Ferrite
//
//  Created by Brian Dashore on 12/31/22.
//

import SwiftUI

struct RealDebridCloudView: View {
    @EnvironmentObject var navModel: NavigationViewModel
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var pluginManager: PluginManager

    @Binding var searchText: String

    var body: some View {
        Group {
            DisclosureGroup("Downloads") {
                ForEach(debridManager.realDebridCloudDownloads.filter {
                    searchText.isEmpty ? true : $0.fileName.lowercased().contains(searchText.lowercased())
                }, id: \.self) { cloudDownload in
                    Button(cloudDownload.fileName) {
                        navModel.resultFromCloud = true
                        navModel.selectedTitle = cloudDownload.fileName
                        debridManager.downloadUrl = cloudDownload.link

                        PersistenceController.shared.createHistory(
                            HistoryEntryJson(
                                name: cloudDownload.fileName,
                                url: cloudDownload.link,
                                source: DebridType.realDebrid.toString()
                            ),
                            performSave: true
                        )

                        pluginManager.runDefaultAction(
                            urlString: debridManager.downloadUrl,
                            navModel: navModel
                        )
                    }
                    .disabledAppearance(navModel.currentChoiceSheet != nil, dimmedOpacity: 0.7, animation: .easeOut(duration: 0.2))
                    .tint(.primary)
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let cloudDownload = debridManager.realDebridCloudDownloads[safe: index] {
                            Task {
                                await debridManager.deleteRdDownload(downloadID: cloudDownload.downloadId)
                            }
                        }
                    }
                }
            }

            DisclosureGroup("Torrents") {
                ForEach(debridManager.realDebridCloudTorrents.filter {
                    searchText.isEmpty ? true : $0.fileName.lowercased().contains(searchText.lowercased())
                }, id: \.self) { cloudTorrent in
                    Button {
                        if cloudTorrent.status == "downloaded", !cloudTorrent.links.isEmpty {
                            navModel.resultFromCloud = true
                            navModel.selectedTitle = cloudTorrent.fileName

                            var historyInfo = HistoryEntryJson(
                                name: cloudTorrent.fileName,
                                source: DebridType.realDebrid.toString()
                            )

                            Task {
                                let magnet = Magnet(hash: cloudTorrent.hash, link: nil)
                                await debridManager.populateDebridIA([magnet])
                                if debridManager.selectDebridResult(magnet: magnet) {
                                    // Is this a batch?

                                    if cloudTorrent.links.count == 1 {
                                        await debridManager.fetchDebridDownload(magnet: magnet)

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
                                DebridLabelView(cloudLinks: cloudTorrent.links)
                            }
                            .font(.caption)
                        }
                    }
                    .disabledAppearance(navModel.currentChoiceSheet != nil, dimmedOpacity: 0.7, animation: .easeOut(duration: 0.2))
                    .tint(.primary)
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let cloudTorrent = debridManager.realDebridCloudTorrents[safe: index] {
                            Task {
                                await debridManager.deleteRdTorrent(torrentID: cloudTorrent.torrentId)
                            }
                        }
                    }
                }
            }
        }
    }
}
