//
//  DebridManager.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/20/22.
//

import Foundation
import SwiftUI

@MainActor
class DebridManager: ObservableObject {
    // Linked classes
    var logManager: LoggingManager?
    @Published var realDebrid: RealDebrid = .init()
    @Published var allDebrid: AllDebrid = .init()
    @Published var premiumize: Premiumize = .init()
    @Published var torbox: TorBox = .init()
    @Published var offcloud: OffCloud = .init()

    lazy var debridSources: [DebridSource] = [realDebrid, allDebrid, premiumize, torbox, offcloud]

    // UI Variables
    @Published var showWebView: Bool = false
    @Published var showAuthSession: Bool = false
    @Published var enabledDebrids: [DebridSource] = []

    @Published var selectedDebridSource: DebridSource? {
        didSet {
            UserDefaults.standard.set(selectedDebridSource?.id ?? "", forKey: "Debrid.PreferredService")
        }
    }

    var selectedDebridItem: DebridIA?
    var selectedDebridFile: DebridIAFile?
    var requiresUnrestrict: Bool = false

    // TODO: Figure out a way to remove this var
    private var selectedOAuthDebridSource: OAuthDebridSource?

    @Published var filteredIAStatus: Set<IAStatus> = []

    var currentDebridTask: Task<Void, Never>?
    var downloadUrl: String = ""
    var authUrl: URL?

    @Published var showDeleteAlert: Bool = false
    @Published var showWebLoginAlert: Bool = false
    @Published var showNotImplementedAlert: Bool = false
    @Published var notImplementedMessage: String = ""

    init() {
        // Update the UI for debrid services that are enabled
        enabledDebrids = debridSources.filter(\.isLoggedIn)

        // Set the preferred service. Contains migration logic for earlier versions
        if let rawPreferredService = UserDefaults.standard.string(forKey: "Debrid.PreferredService") {
            let debridServiceId: String?

            if let preferredServiceInt = Int(rawPreferredService) {
                debridServiceId = migratePreferredService(preferredServiceInt)
            } else {
                debridServiceId = rawPreferredService
            }

            // Only set the debrid source if it's logged in
            // Otherwise remove the key
            let tempDebridSource = debridSources.first { $0.id == debridServiceId }
            if tempDebridSource?.isLoggedIn ?? false {
                selectedDebridSource = tempDebridSource
            } else {
                UserDefaults.standard.removeObject(forKey: "Debrid.PreferredService")
            }
        }
    }

    // TODO: Remove after v0.8.0
    // Function to migrate the preferred service to the new string ID format
    private func migratePreferredService(_ idInt: Int) -> String? {
        // Undo the EnabledDebrids key
        UserDefaults.standard.removeObject(forKey: "Debrid.EnabledArray")

        return DebridType(rawValue: idInt)?.toString()
    }

    // Wrapper function to match error descriptions
    // Error can be suppressed to end user but must be printed in logs
    private func sendDebridError(
        _ error: Error,
        prefix: String,
        presentError: Bool = true,
        cancelString: String? = nil
    ) async {
        let error = error as NSError
        if presentError {
            switch error.code {
            case -1009:
                logManager?.info(
                    "DebridManager: The connection is offline",
                    description: "The connection is offline"
                )
            case -999:
                if let cancelString {
                    logManager?.info(cancelString, description: cancelString)
                } else {
                    break
                }
            default:
                logManager?.error("\(prefix): \(error)")
            }
        }
    }

    // Cleans all cached IA values in the event of a full IA refresh
    func clearIAValues() {
        for debridSource in debridSources {
            debridSource.IAValues = []
        }
    }

    // Clears all selected files and items
    func clearSelectedDebridItems() {
        selectedDebridItem = nil
        selectedDebridFile = nil
    }

    // Common function to populate hashes for debrid services
    func populateDebridIA(_ resultMagnets: [Magnet]) async {
        for debridSource in debridSources {
            if !debridSource.isLoggedIn {
                continue
            }

            // Don't exit the function if the API fetch errors
            do {
                try await debridSource.instantAvailability(magnets: resultMagnets)
            } catch {
                await sendDebridError(error, prefix: "\(debridSource.id) IA fetch error")
            }
        }
    }

    // Common function to match a magnet hash with a provided debrid service
    func matchMagnetHash(_ magnet: Magnet) -> IAStatus {
        guard let magnetHash = magnet.hash else {
            return .none
        }

        if let selectedDebridSource,
           let match = selectedDebridSource.IAValues.first(where: { magnetHash == $0.magnet.hash })
        {
            return match.files.count > 1 ? .partial : .full
        } else {
            return .none
        }
    }

    func selectDebridResult(magnet: Magnet) -> Bool {
        guard let magnetHash = magnet.hash else {
            logManager?.error("DebridManager: Could not find the magnet hash")
            return false
        }

        guard let selectedSource = selectedDebridSource else {
            return false
        }

        if let IAItem = selectedSource.IAValues.first(where: { magnetHash == $0.magnet.hash }) {
            selectedDebridItem = IAItem

            if IAItem.files.count == 1 {
                selectedDebridFile = IAItem.files[safe: 0]
            }

            return true
        } else {
            logManager?.error("DebridManager: Could not find the associated \(selectedSource.id) entry for magnet hash \(magnetHash)")
            return false
        }
    }

    // MARK: - Authentication UI linked functions

    // Common function to delegate what debrid service to authenticate with
    func authenticateDebrid(_ debridSource: some DebridSource, apiKey: String?) async {
        defer {
            // Don't cancel processing if using OAuth
            if !(debridSource is OAuthDebridSource) {
                debridSource.authProcessing = false
            }

            if enabledDebrids.count == 1 {
                selectedDebridSource = debridSource
            }
        }

        // Set an API key if manually provided
        if let apiKey {
            debridSource.setApiKey(apiKey)
            enabledDebrids.append(debridSource)

            return
        }

        // Processing has started
        debridSource.authProcessing = true

        if let pollingSource = debridSource as? PollingDebridSource {
            do {
                let authUrl = try await pollingSource.getAuthUrl()

                if validateAuthUrl(authUrl) {
                    try await pollingSource.authTask?.value
                    enabledDebrids.append(debridSource)
                } else {
                    throw DebridError.AuthQuery(description: "The authentication URL was invalid")
                }
            } catch {
                await sendDebridError(error, prefix: "\(debridSource.id) authentication error")

                pollingSource.authTask?.cancel()
            }
        } else if let oauthSource = debridSource as? OAuthDebridSource {
            do {
                let tempAuthUrl = try oauthSource.getAuthUrl()
                selectedOAuthDebridSource = oauthSource

                validateAuthUrl(tempAuthUrl, useAuthSession: true)
            } catch {
                await sendDebridError(error, prefix: "\(debridSource.id) authentication error")
            }
        } else {
            // Let the user know that a traditional auth method doesn't exist
            showWebLoginAlert.toggle()

            logManager?.error(
                "DebridManager: Auth: \(debridSource.id) does not have a login portal.",
                showToast: false
            )

            return
        }
    }

    // Get a truncated manual API key if it's being used
    func getManualAuthKey(_ debridSource: some DebridSource) async -> String? {
        if let debridToken = debridSource.manualToken {
            let splitString = debridToken.suffix(4)

            if debridToken.count > 4 {
                return String(repeating: "*", count: debridToken.count - 4) + splitString
            } else {
                return String(splitString)
            }
        } else {
            return nil
        }
    }

    // Wrapper function to validate and present an auth URL to the user
    @discardableResult private func validateAuthUrl(_ url: URL?, useAuthSession: Bool = false) -> Bool {
        guard let url else {
            logManager?.error("DebridManager: Authentication: Invalid URL created: \(String(describing: url))")
            return false
        }

        authUrl = url
        if useAuthSession {
            showAuthSession.toggle()
        } else {
            showWebView.toggle()
        }

        return true
    }

    // Currently handles Premiumize callback
    func handleAuthCallback(url: URL?, error: Error?) async {
        defer {
            if enabledDebrids.count == 1 {
                selectedDebridSource = selectedOAuthDebridSource
            }

            selectedOAuthDebridSource?.authProcessing = false
        }

        do {
            guard let oauthDebridSource = selectedOAuthDebridSource else {
                throw DebridError.AuthQuery(description: "OAuth source couldn't be found for callback. Aborting.")
            }

            if let error {
                throw DebridError.AuthQuery(description: "OAuth callback Error: \(error)")
            }

            if let callbackUrl = url {
                try oauthDebridSource.handleAuthCallback(url: callbackUrl)
                enabledDebrids.append(oauthDebridSource)
            } else {
                throw DebridError.AuthQuery(description: "The callback URL was invalid")
            }
        } catch {
            await sendDebridError(error, prefix: "Premiumize authentication error (callback)")
        }
    }

    // MARK: - Logout UI functions

    func logout(_ debridSource: some DebridSource) async {
        await debridSource.logout()

        if selectedDebridSource?.id == debridSource.id {
            selectedDebridSource = nil
        }

        enabledDebrids.removeAll { $0.id == debridSource.id }
    }

    // MARK: - Debrid fetch UI linked functions

    // Common function to delegate what debrid service to fetch from
    // Cloudinfo is used for any extra information provided by debrid cloud
    func fetchDebridDownload(magnet: Magnet?, cloudInfo: String? = nil) async {
        defer {
            logManager?.hideIndeterminateToast()

            if !requiresUnrestrict {
                clearSelectedDebridItems()
            }

            currentDebridTask = nil
        }

        logManager?.updateIndeterminateToast("Loading content", cancelAction: {
            self.currentDebridTask?.cancel()
            self.currentDebridTask = nil
        })

        guard let debridSource = selectedDebridSource else {
            return
        }

        do {
            // Cleanup beforehand
            requiresUnrestrict = false

            if let cloudInfo {
                downloadUrl = try await debridSource.checkUserDownloads(link: cloudInfo) ?? ""
                return
            }

            if let magnet {
                let (restrictedFile, newIA) = try await debridSource.getRestrictedFile(
                    magnet: magnet, ia: selectedDebridItem, iaFile: selectedDebridFile
                )

                // Indicate that a link needs to be selected (batch)
                if let newIA {
                    if newIA.files.isEmpty {
                        throw DebridError.EmptyData
                    }

                    selectedDebridItem = newIA
                    requiresUnrestrict = true

                    return
                }

                guard let restrictedFile else {
                    throw DebridError.FailedRequest(description: "No files found for your request")
                }

                // Update the UI
                downloadUrl = try await debridSource.unrestrictFile(restrictedFile)
            } else {
                throw DebridError.FailedRequest(description: "Could not fetch your file from \(debridSource.id)'s cache or API")
            }

            // Fetch one more time to add updated data into the RD cloud cache
            await fetchDebridCloud(bypassTTL: true)
        } catch {
            switch error {
            case DebridError.IsCaching:
                showDeleteAlert.toggle()
            default:
                await sendDebridError(error, prefix: "\(debridSource.id) download error", cancelString: "Download cancelled")
            }
        }
    }

    func unrestrictDownload() async {
        defer {
            logManager?.hideIndeterminateToast()
            requiresUnrestrict = false
            clearSelectedDebridItems()
            currentDebridTask = nil
        }

        logManager?.updateIndeterminateToast("Loading content", cancelAction: {
            self.currentDebridTask?.cancel()
            self.currentDebridTask = nil
        })

        guard let debridFile = selectedDebridFile, let debridSource = selectedDebridSource else {
            logManager?.error("DebridManager: Could not unrestrict the selected debrid file.")

            return
        }

        do {
            let downloadLink = try await debridSource.unrestrictFile(debridFile)

            downloadUrl = downloadLink
        } catch {
            await sendDebridError(error, prefix: "\(debridSource.id) unrestrict error", cancelString: "Unrestrict cancelled")
        }
    }

    // Wrapper to handle cloud fetching
    func fetchDebridCloud(bypassTTL: Bool = false) async {
        guard let selectedSource = selectedDebridSource else {
            return
        }

        if bypassTTL || Date().timeIntervalSince1970 > selectedSource.cloudTTL {
            do {
                // Populates the inner downloads and magnet arrays
                try await selectedSource.getUserDownloads()
                try await selectedSource.getUserMagnets()

                // Update the TTL to 5 minutes from now
                selectedSource.cloudTTL = Date().timeIntervalSince1970 + 300
            } catch {
                let error = error as NSError
                if error.code != -999 {
                    await sendDebridError(error, prefix: "\(selectedSource.id) cloud fetch error")
                }
            }
        }
    }

    func deleteCloudDownload(_ download: DebridCloudDownload) async {
        guard let selectedSource = selectedDebridSource else {
            return
        }

        do {
            try await selectedSource.deleteUserDownload(downloadId: download.id)

            await fetchDebridCloud(bypassTTL: true)
        } catch {
            switch error {
            case DebridError.NotImplemented:
                let message = "Download deletion for \(selectedSource.id) is not implemented. Please delete from the service's website."

                notImplementedMessage = message
                showNotImplementedAlert.toggle()
                logManager?.error(
                    "DebridManager: \(message)",
                    showToast: false
                )
            default:
                await sendDebridError(error, prefix: "\(selectedSource.id) download delete error")
            }
        }
    }

    func deleteUserMagnet(_ cloudMagnet: DebridCloudMagnet) async {
        guard let selectedSource = selectedDebridSource else {
            return
        }

        do {
            try await selectedSource.deleteUserMagnet(cloudMagnetId: cloudMagnet.id)

            await fetchDebridCloud(bypassTTL: true)
        } catch {
            switch error {
            case DebridError.NotImplemented:
                let message = "Magnet deletion for \(selectedSource.id) is not implemented. Please use the service's website."

                notImplementedMessage = message
                showNotImplementedAlert.toggle()
                logManager?.error(
                    "DebridManager: \(message)",
                    showToast: false
                )
            default:
                await sendDebridError(error, prefix: "\(selectedSource.id) magnet delete error")
            }
        }
    }
}
