//
//  DebridInfoView.swift
//  Ferrite
//
//  Created by Brian Dashore on 3/5/23.
//

import SwiftUI

struct SettingsDebridInfoView: View {
    @EnvironmentObject var debridManager: DebridManager

    @Store var debridSource: DebridSource

    @State private var apiKeyTempText: String = ""

    var body: some View {
        List {
            Section("Description") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(debridSource.description ??
                        "\(debridSource.id) is a debrid service that is used for downloads and media playback. You must pay to access the service."
                    )

                    Link("Website", destination: URL(string: debridSource.website) ?? URL(string: "https://kingbri.dev/ferrite")!)
                }
            }

            Section(
                header: Text("Login status"),
                footer: Text("A WebView will show up to prompt you for credentials")
            ) {
                Button {
                    Task {
                        if debridSource.isLoggedIn {
                            await debridManager.logout(debridSource)
                        } else if !debridSource.authProcessing {
                            await debridManager.authenticateDebrid(debridSource, apiKey: nil)
                        }

                        apiKeyTempText = await debridManager.getManualAuthKey(debridSource) ?? ""
                    }
                } label: {
                    Text(
                        debridSource.isLoggedIn
                            ? "Logout"
                            : (debridSource.authProcessing ? "Processing" : "Login")
                    )
                    .foregroundColor(debridSource.isLoggedIn ? .red : .blue)
                }
                .alert("Invalid web login", isPresented: $debridManager.showWebLoginAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(
                        "\(debridSource.id) does not have a login portal. Please use an API key to login."
                    )
                }
            }

            Section(
                header: Text("API key"),
                footer: Text("Add a permanent API key here. Only use this if web authentication does not work!")
            ) {
                HybridSecureField(
                    text: $apiKeyTempText,
                    onCommit: {
                        Task {
                            if !apiKeyTempText.isEmpty {
                                await debridManager.authenticateDebrid(debridSource, apiKey: apiKeyTempText)
                                apiKeyTempText = await debridManager.getManualAuthKey(debridSource) ?? ""
                            }
                        }
                    }
                )
                .fieldDisabled(debridSource.isLoggedIn)
            }
            .onAppear {
                Task {
                    apiKeyTempText = await debridManager.getManualAuthKey(debridSource) ?? ""
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(debridSource.id)
        .navigationBarTitleDisplayMode(.inline)
    }
}
