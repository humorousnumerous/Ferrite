//
//  DebridCloudView.swift
//  Ferrite
//
//  Created by Brian Dashore on 12/31/22.
//

import SwiftUI

struct DebridCloudView: View {
    @EnvironmentObject var debridManager: DebridManager

    @Store var debridSource: DebridSource

    @Binding var searchText: String

    var body: some View {
        List {
            if !debridSource.cloudDownloads.isEmpty {
                CloudDownloadView(debridSource: debridSource, searchText: $searchText)
            }

            if !debridSource.cloudTorrents.isEmpty {
                CloudTorrentView(debridSource: debridSource, searchText: $searchText)
            }
        }
        .listStyle(.plain)
        .task {
            await debridManager.fetchDebridCloud()
        }
        .refreshable {
            await debridManager.fetchDebridCloud(bypassTTL: true)
        }
        .onChange(of: debridManager.selectedDebridSource?.id) { newType in
            if newType != nil {
                Task {
                    await debridManager.fetchDebridCloud()
                }
            }
        }
    }
}
