//
//  SettingsView.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/11/22.
//

import BetterSafariView
import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var debridManager: DebridManager
    @EnvironmentObject var pluginManager: PluginManager

    let backgroundContext = PersistenceController.shared.backgroundContext

    @FetchRequest(
        entity: KodiServer.entity(),
        sortDescriptors: []
    ) var kodiServers: FetchedResults<KodiServer>

    @AppStorage("ExternalServices.KodiUrl") var kodiUrl: String = ""

    @AppStorage("Behavior.AutocorrectSearch") var autocorrectSearch = true
    @AppStorage("Behavior.UsesRandomSearchText") var usesRandomSearchText = false
    @AppStorage("Behavior.UseEphemeralAuth") var useEphemeralAuth = true
    @AppStorage("Behavior.DisableRequestTimeout") var disableRequestTimeout = false
    @AppStorage("Behavior.RequestTimeoutSecs") var requestTimeoutSecs: Double = 15

    @AppStorage("Updates.AutomaticNotifs") var autoUpdateNotifs = true

    @AppStorage("Actions.DefaultMagnet") var defaultMagnetAction: CodableWrapper<DefaultAction> = .init(value: .none)
    @AppStorage("Actions.DefaultDebrid") var defaultDebridAction: CodableWrapper<DefaultAction> = .init(value: .none)

    @AppStorage("Debug.ShowErrorToasts") var showErrorToasts = true

    private enum Field {
        case requestTimeout
    }

    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("Debrid services") {
                    ForEach(debridManager.debridSources, id: \.id) { (debridSource: DebridSource) in
                        NavigationLink {
                            SettingsDebridInfoView(debridSource: debridSource)
                        } label: {
                            HStack {
                                Text(debridSource.id)
                                Spacer()
                                Text(debridSource.isLoggedIn ? "Enabled" : "Disabled")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Playback services") {
                    NavigationLink {
                        SettingsKodiView(kodiServers: kodiServers)
                    } label: {
                        HStack {
                            Text("Kodi")
                            Spacer()
                            Text(kodiServers.isEmpty ? "Disabled" : "Enabled")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(
                    header: Text("Behavior"),
                    footer: VStack(alignment: .leading, spacing: 8) {
                        Text("Temporarily disable ephemeral auth if you cannot log into a service")
                        Text("Only disable search timeout if results are slow to fetch")
                    }
                ) {
                    Toggle(isOn: $autocorrectSearch) {
                        Text("Autocorrect search")
                    }

                    Toggle(isOn: $usesRandomSearchText) {
                        Text("Random searchbar text")
                    }

                    Toggle(isOn: $useEphemeralAuth) {
                        Text("Ephemeral authentication")
                    }
                    .onChange(of: useEphemeralAuth) { changed in
                        // Does not work with ASWebAuthenticationSession
                        if changed {
                            Task {
                                let dataRecords = await WKWebsiteDataStore.default().dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())

                                await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: dataRecords)
                            }
                        }
                    }

                    // TODO: Change this to enable search timeout instead
                    Toggle(isOn: $disableRequestTimeout) {
                        Text("Disable search timeout")
                    }

                    if !disableRequestTimeout {
                        HStack {
                            Text("Search timeout seconds")

                            Spacer()

                            TextField("", value: $requestTimeoutSecs, formatter: NumberFormatter())
                                .fixedSize()
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: Field.requestTimeout)
                        }
                    }
                }

                Section("Plugin management") {
                    NavigationLink("Plugin lists") {
                        SettingsPluginListView()
                    }
                }

                Section("Default actions") {
                    if !debridManager.enabledDebrids.isEmpty {
                        NavigationLink {
                            DefaultActionPickerView(
                                actionRequirement: .debrid,
                                defaultAction: $defaultDebridAction.value,
                                kodiServers: kodiServers
                            )
                        } label: {
                            HStack {
                                Text("Debrid action")
                                Spacer()

                                Group {
                                    switch defaultDebridAction.value {
                                    case .none:
                                        Text("User choice")
                                    case .share:
                                        Text("Share")
                                    case .kodi:
                                        Text("Kodi")
                                    case let .custom(name, _):
                                        Text(name)
                                    }
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        DefaultActionPickerView(
                            actionRequirement: .magnet,
                            defaultAction: $defaultMagnetAction.value,
                            kodiServers: kodiServers
                        )
                    } label: {
                        HStack {
                            Text("Magnet action")
                            Spacer()

                            Group {
                                switch defaultMagnetAction.value {
                                case .none:
                                    Text("User choice")
                                case .share:
                                    Text("Share")
                                case .kodi:
                                    Text("Kodi")
                                case let .custom(name, _):
                                    Text(name)
                                }
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Backups") {
                    NavigationLink("Backups") {
                        BackupsView()
                    }
                }

                Section("Updates") {
                    Toggle(isOn: $autoUpdateNotifs) {
                        Text("Show update alerts")
                    }

                    NavigationLink("Version history") {
                        SettingsAppVersionView()
                    }
                }

                Section("Information") {
                    ListRowLinkView(text: "Donate", link: "https://ko-fi.com/kingbri")
                    ListRowLinkView(text: "Report issues", link: "https://github.com/bdashore3/Ferrite/issues")

                    NavigationLink("About") {
                        AboutView()
                    }
                }

                Section("Debug") {
                    NavigationLink("Logs") {
                        SettingsLogView()
                    }

                    Toggle("Show error alerts", isOn: $showErrorToasts)
                }
            }
            .sheet(isPresented: $debridManager.showWebView) {
                LoginWebView(url: debridManager.authUrl ?? URL(string: "https://google.com")!)
            }
            .webAuthenticationSession(isPresented: $debridManager.showAuthSession) {
                WebAuthenticationSession(
                    url: debridManager.authUrl ?? URL(string: "https://google.com")!,
                    callbackURLScheme: "ferrite"
                ) { callbackURL, error in
                    Task {
                        await debridManager.handleAuthCallback(url: callbackURL, error: error)
                    }
                }
                .prefersEphemeralWebBrowserSession(useEphemeralAuth)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
