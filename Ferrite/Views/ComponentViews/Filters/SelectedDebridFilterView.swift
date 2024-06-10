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
                debridManager.selectedDebridSource = nil
            } label: {
                Text("None")

                if debridManager.selectedDebridSource == nil {
                    Image(systemName: "checkmark")
                }
            }

            ForEach(debridManager.debridSources, id: \.id) { debridSource in
                if debridSource.isLoggedIn {
                    Button {
                        debridManager.selectedDebridSource = debridSource
                    } label: {
                        Text(debridSource.id)

                        if debridManager.selectedDebridSource?.id == debridSource.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            label
        }
    }
}
