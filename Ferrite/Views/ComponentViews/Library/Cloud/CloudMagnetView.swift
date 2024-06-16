//
//  CloudMagnetView.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/6/24.
//

import SwiftUI

struct CloudMagnetView: View {
    @EnvironmentObject var navModel: NavigationViewModel
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var pluginManager: PluginManager

    @Store var debridSource: DebridSource

    @Binding var searchText: String

    var body: some View {
        DisclosureGroup("Magnets") {
            ForEach(debridSource.cloudMagnets.filter {
                searchText.isEmpty ? true : $0.fileName.lowercased().contains(searchText.lowercased())
            }, id: \.self) { cloudMagnet in
                Button {
                    if cloudMagnet.status == "downloaded", !cloudMagnet.links.isEmpty {
                        navModel.resultFromCloud = true
                        navModel.selectedTitle = cloudMagnet.fileName

                        var historyInfo = HistoryEntryJson(
                            name: cloudMagnet.fileName,
                            source: debridSource.id
                        )

                        Task {
                            let magnet = Magnet(hash: cloudMagnet.hash, link: nil)
                            await debridManager.populateDebridIA([magnet])
                            if debridManager.selectDebridResult(magnet: magnet) {
                                // Is this a batch?

                                if cloudMagnet.links.count == 1 {
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
                        Text(cloudMagnet.fileName)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)

                        HStack {
                            Text(cloudMagnet.status.capitalizingFirstLetter())
                            Spacer()
                            DebridLabelView(debridSource: debridSource, cloudLinks: cloudMagnet.links)
                        }
                        .font(.caption)
                    }
                }
                .disabledAppearance(navModel.currentChoiceSheet != nil, dimmedOpacity: 0.7, animation: .easeOut(duration: 0.2))
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    if let cloudMagnet = debridSource.cloudMagnets[safe: index] {
                        Task {
                            await debridManager.deleteUserMagnet(cloudMagnet)
                        }
                    }
                }
            }
        }
    }
}
