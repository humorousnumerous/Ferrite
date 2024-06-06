//
//  DebridManager.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/20/22.
//

import Foundation
import SwiftUI

@MainActor
public class DebridManager: ObservableObject {
    // Linked classes
    var logManager: LoggingManager?
    @Published var realDebrid: RealDebrid = .init()
    @Published var allDebrid: AllDebrid = .init()
    @Published var premiumize: Premiumize = .init()

    lazy var debridSources: [DebridSource] = [realDebrid, allDebrid, premiumize]

    // UI Variables
    @Published var showWebView: Bool = false
    @Published var showAuthSession: Bool = false

    var hasEnabledDebrids: Bool {
        debridSources.contains { $0.isLoggedIn }
    }

    @Published var selectedDebridSource: DebridSource? {
        didSet {
            UserDefaults.standard.set(selectedDebridSource?.id ?? "", forKey: "Debrid.PreferredService")
        }
    }
    var selectedDebridItem: DebridIA?
    var selectedDebridFile: DebridIAFile?

    // Service agnostic variables
    @Published var enabledDebrids: Set<DebridType> = [] {
        didSet {
            UserDefaults.standard.set(enabledDebrids.rawValue, forKey: "Debrid.EnabledArray")
        }
    }

    @Published var selectedDebridType: DebridType? {
        didSet {
            UserDefaults.standard.set(selectedDebridType?.rawValue ?? 0, forKey: "Debrid.PreferredService")
        }
    }

    @Published var filteredIAStatus: Set<IAStatus> = []

    var currentDebridTask: Task<Void, Never>?
    var downloadUrl: String = ""
    var authUrl: URL?

    // Is the current debrid type processing an auth request
    func authProcessing(_ passedDebridType: DebridType?) -> Bool {
        guard let debridType = passedDebridType ?? selectedDebridType else {
            return false
        }

        switch debridType {
        case .realDebrid:
            return realDebridAuthProcessing
        case .allDebrid:
            return allDebridAuthProcessing
        case .premiumize:
            return premiumizeAuthProcessing
        }
    }

    // RealDebrid auth variables
    var realDebridAuthProcessing: Bool = false

    @Published var showDeleteAlert: Bool = false

    // AllDebrid auth variables
    var allDebridAuthProcessing: Bool = false

    // Premiumize auth variables
    var premiumizeAuthProcessing: Bool = false

    init() {

        // Set the preferred service. Contains migration logic for earlier versions
        if let rawPreferredService = UserDefaults.standard.string(forKey: "Debrid.PreferredService") {
            let debridServiceId: String?

            if let preferredServiceInt = Int(rawPreferredService) {
                debridServiceId = migratePreferredService(preferredServiceInt)
            } else {
                print(rawPreferredService)
                debridServiceId = rawPreferredService
            }

            // Only set the debrid source if it's logged in
            // Otherwise remove the key
            let tempDebridSource = self.debridSources.first { $0.id == debridServiceId }
            if (tempDebridSource?.isLoggedIn ?? false) {
                selectedDebridSource = tempDebridSource
            } else {
                UserDefaults.standard.removeObject(forKey: "Debrid.PreferredService")
            }
        }
    }

    // TODO: Remove after v0.8.0
    // Function to migrate the preferred service to the new string ID format
    public func migratePreferredService(_ idInt: Int) -> String? {
        // Undo the EnabledDebrids key
        UserDefaults.standard.removeObject(forKey: "Debrid.EnabledArray")

        return DebridType(rawValue: idInt)?.toString()
    }

    // Wrapper function to match error descriptions
    // Error can be suppressed to end user but must be printed in logs
    func sendDebridError(
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
    public func clearIAValues() {
        for debridSource in debridSources {
            debridSource.IAValues = []
        }
    }

    // Clears all selected files and items
    public func clearSelectedDebridItems() {
        selectedDebridItem = nil
        selectedDebridFile = nil
    }

    // Common function to populate hashes for debrid services
    public func populateDebridIA(_ resultMagnets: [Magnet]) async {
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
    public func matchMagnetHash(_ magnet: Magnet) -> IAStatus {
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

    public func selectDebridResult(magnet: Magnet) -> Bool {
        guard let magnetHash = magnet.hash else {
            logManager?.error("DebridManager: Could not find the torrent magnet hash")
            return false
        }

        guard let selectedSource = selectedDebridSource else {
            return false
        }

        if let IAItem = selectedSource.IAValues.first(where: { magnetHash == $0.magnet.hash }) {
            selectedDebridItem = IAItem
            return true
        } else {
            logManager?.error("DebridManager: Could not find the associated \(selectedSource.id) entry for magnet hash \(magnetHash)")
            return false
        }
    }

    // MARK: - Authentication UI linked functions

    // Common function to delegate what debrid service to authenticate with
    public func authenticateDebrid(debridType: DebridType, apiKey: String?) async {
        switch debridType {
        case .realDebrid:
            let success = apiKey == nil ? await authenticateRd() : realDebrid.setApiKey(apiKey!)
            completeDebridAuth(debridType, success: success)
        case .allDebrid:
            // Async can't work with nil mapping method
            let success = apiKey == nil ? await authenticateAd() : allDebrid.setApiKey(apiKey!)
            completeDebridAuth(debridType, success: success)
        case .premiumize:
            if let apiKey {
                let success = premiumize.setApiKey(apiKey)
                completeDebridAuth(debridType, success: success)
            } else {
                await authenticatePm()
            }
        }
    }

    // Callback to finish debrid auth since functions can be split
    func completeDebridAuth(_ debridType: DebridType, success: Bool) {
        if success {
            enabledDebrids.insert(debridType)
            if enabledDebrids.count == 1 {
                selectedDebridType = enabledDebrids.first
            }
        }

        switch debridType {
        case .realDebrid:
            realDebridAuthProcessing = false
        case .allDebrid:
            allDebridAuthProcessing = false
        case .premiumize:
            premiumizeAuthProcessing = false
        }
    }

    // Get a truncated manual API key if it's being used
    func getManualAuthKey(_ passedDebridType: DebridType?) async -> String? {
        guard let debridType = passedDebridType ?? selectedDebridType else {
            return nil
        }

        let debridToken: String?
        switch debridType {
        case .realDebrid:
            if UserDefaults.standard.bool(forKey: "RealDebrid.UseManualKey") {
                debridToken = FerriteKeychain.shared.get("RealDebrid.AccessToken")
            } else {
                debridToken = nil
            }
        case .allDebrid:
            if UserDefaults.standard.bool(forKey: "AllDebrid.UseManualKey") {
                debridToken = FerriteKeychain.shared.get("AllDebrid.ApiKey")
            } else {
                debridToken = nil
            }
        case .premiumize:
            if UserDefaults.standard.bool(forKey: "Premiumize.UseManualKey") {
                debridToken = FerriteKeychain.shared.get("Premiumize.AccessToken")
            } else {
                debridToken = nil
            }
        }

        if let debridToken {
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
    @discardableResult func validateAuthUrl(_ url: URL?, useAuthSession: Bool = false) -> Bool {
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

    private func authenticateRd() async -> Bool {
        do {
            realDebridAuthProcessing = true
            let authUrl = try await realDebrid.getAuthUrl()

            if validateAuthUrl(authUrl) {
                try await realDebrid.authTask?.value
                return true
            } else {
                throw DebridError.AuthQuery(description: "The verification URL was invalid")
            }
        } catch {
            await sendDebridError(error, prefix: "RealDebrid authentication error")

            realDebrid.authTask?.cancel()
            return false
        }
    }

    private func authenticateAd() async -> Bool {
        do {
            allDebridAuthProcessing = true
            let authUrl = try await allDebrid.getAuthUrl()

            if validateAuthUrl(authUrl) {
                try await allDebrid.authTask?.value
                return true
            } else {
                throw DebridError.AuthQuery(description: "The PIN URL was invalid")
            }
        } catch {
            await sendDebridError(error, prefix: "AllDebrid authentication error")

            allDebrid.authTask?.cancel()
            return false
        }
    }

    private func authenticatePm() async {
        do {
            premiumizeAuthProcessing = true
            let tempAuthUrl = try premiumize.getAuthUrl()

            validateAuthUrl(tempAuthUrl, useAuthSession: true)
        } catch {
            await sendDebridError(error, prefix: "Premiumize authentication error")

            completeDebridAuth(.premiumize, success: false)
        }
    }

    // Currently handles Premiumize callback
    public func handleCallback(url: URL?, error: Error?) async {
        do {
            if let error {
                throw DebridError.AuthQuery(description: "OAuth callback Error: \(error)")
            }

            if let callbackUrl = url {
                try premiumize.handleAuthCallback(url: callbackUrl)
                completeDebridAuth(.premiumize, success: true)
            } else {
                throw DebridError.AuthQuery(description: "The callback URL was invalid")
            }
        } catch {
            await sendDebridError(error, prefix: "Premiumize authentication error (callback)")

            completeDebridAuth(.premiumize, success: false)
        }
    }

    // MARK: - Debrid fetch UI linked functions

    // Common function to delegate what debrid service to fetch from
    // Cloudinfo is used for any extra information provided by debrid cloud
    public func fetchDebridDownload(magnet: Magnet?, cloudInfo: String? = nil) async {
        defer {
            currentDebridTask = nil
            logManager?.hideIndeterminateToast()
        }

        logManager?.updateIndeterminateToast("Loading content", cancelAction: {
            self.currentDebridTask?.cancel()
            self.currentDebridTask = nil
        })

        guard let debridSource = selectedDebridSource else {
            return
        }

        do {
            if let cloudInfo {
                downloadUrl = try await debridSource.checkUserDownloads(link: cloudInfo) ?? ""
                return
            }

            if let magnet {
                let downloadLink = try await debridSource.getDownloadLink(
                    magnet: magnet, ia: selectedDebridItem, iaFile: selectedDebridFile
                )

                // Update the UI
                downloadUrl = downloadLink
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

            logManager?.hideIndeterminateToast()
        }
    }

    // Wrapper to handle cloud fetching
    public func fetchDebridCloud(bypassTTL: Bool = false) async {
        guard let selectedSource = selectedDebridSource else {
            return
        }

        if bypassTTL || Date().timeIntervalSince1970 > selectedSource.cloudTTL {
            do {
                // Populates the inner downloads and torrent arrays
                try await selectedSource.getUserDownloads()
                try await selectedSource.getUserTorrents()

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

    public func deleteCloudDownload(_ download: DebridCloudDownload) async {
        guard let selectedSource = selectedDebridSource else {
            return
        }

        do {
            try await selectedSource.deleteDownload(downloadId: download.downloadId)

            await fetchDebridCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "\(selectedSource.id) download delete error")
        }
    }

    public func deleteCloudTorrent(_ torrent: DebridCloudTorrent) async {
        guard let selectedSource = selectedDebridSource else {
            return
        }

        do {
            try await selectedSource.deleteTorrent(torrentId: torrent.torrentId)

            await fetchDebridCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "\(selectedSource.id) torrent delete error")
        }
    }
}
