//
//  SelectedDebridFilterView.swift
//  Ferrite
//
//  Created by Brian Dashore on 4/10/23.
//

import SwiftUI

struct SelectedDebridFilterView<Content: View>: View {
    @EnvironmentObject var debridManager: DebridManager

    @ViewBuilder var label: Content

    var body: some View {
        Menu {
            Button {
                debridManager.selectedDebridId = nil
            } label: {
                Text("None")

                if debridManager.selectedDebridId == nil {
                    Image(systemName: "checkmark")
                }
            }

            ForEach(debridManager.debridSources, id: \.id) { debridSource in
                if debridSource.isLoggedIn {
                    Button {
                        debridManager.selectedDebridId = debridSource.id
                    } label: {
                        Text(debridSource.id.name)

                        if debridManager.selectedDebridId == debridSource.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            label
        }
        .id(debridManager.selectedDebridId)
    }
}
