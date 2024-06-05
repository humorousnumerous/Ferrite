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

    @Published var selectedDebridId: DebridInfo?

    func debridSourceFromName(_ name: String? = nil) -> DebridSource? {
        debridSources.first { $0.id.name == name ?? selectedDebridId?.name }
    }

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

    var selectedRealDebridItem: DebridIA?
    var selectedRealDebridFile: DebridIAFile?
    var selectedRealDebridID: String?

    // TODO: Maybe make these generic?
    // RealDebrid cloud variables
    @Published var realDebridCloudTorrents: [DebridCloudTorrent] = []
    @Published var realDebridCloudDownloads: [DebridCloudDownload] = []
    var realDebridCloudTTL: Double = 0.0

    // AllDebrid auth variables
    var allDebridAuthProcessing: Bool = false

    var selectedAllDebridItem: DebridIA?
    var selectedAllDebridFile: DebridIAFile?

    // AllDebrid cloud variables
    @Published var allDebridCloudMagnets: [DebridCloudTorrent] = []
    @Published var allDebridCloudLinks: [DebridCloudDownload] = []
    var allDebridCloudTTL: Double = 0.0

    // Premiumize auth variables
    var premiumizeAuthProcessing: Bool = false

    var selectedPremiumizeItem: DebridIA?
    var selectedPremiumizeFile: DebridIAFile?

    // Premiumize cloud variables
    @Published var premiumizeCloudItems: [DebridCloudDownload] = []
    var premiumizeCloudTTL: Double = 0.0

    init() {
        if let rawDebridList = UserDefaults.standard.string(forKey: "Debrid.EnabledArray"),
           let serializedDebridList = Set<DebridType>(rawValue: rawDebridList)
        {
            enabledDebrids = serializedDebridList
        }

        // If a UserDefaults integer isn't set, it's usually 0
        let rawPreferredService = UserDefaults.standard.integer(forKey: "Debrid.PreferredService")
        let legacyPreferredService = DebridType(rawValue: rawPreferredService)
        let preferredDebridSource = self.debridSourceFromName(legacyPreferredService?.toString())
        selectedDebridId = preferredDebridSource?.id

        // If a user has one logged in service, automatically set the preferred service to that one
        /*
        if enabledDebrids.count == 1 {
            selectedDebridType = enabledDebrids.first
        }
         */
    }

    // TODO: Remove this after v0.6.0
    // Login cleanup function that's automatically run to switch to the new login system
    public func cleanupOldLogins() async {
        let realDebridEnabled = UserDefaults.standard.bool(forKey: "RealDebrid.Enabled")
        if realDebridEnabled {
            enabledDebrids.insert(.realDebrid)
            UserDefaults.standard.set(false, forKey: "RealDebrid.Enabled")
        }

        let allDebridEnabled = UserDefaults.standard.bool(forKey: "AllDebrid.Enabled")
        if allDebridEnabled {
            enabledDebrids.insert(.allDebrid)
            UserDefaults.standard.set(false, forKey: "AllDebrid.Enabled")
        }

        let premiumizeEnabled = UserDefaults.standard.bool(forKey: "Premiumize.Enabled")
        if premiumizeEnabled {
            enabledDebrids.insert(.premiumize)
            UserDefaults.standard.set(false, forKey: "Premiumize.Enabled")
        }
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
        switch selectedDebridType {
        case .realDebrid:
            selectedRealDebridFile = nil
            selectedRealDebridItem = nil
        case .allDebrid:
            selectedAllDebridFile = nil
            selectedAllDebridItem = nil
        case .premiumize:
            selectedPremiumizeFile = nil
            selectedPremiumizeItem = nil
        case .none:
            break
        }
    }

    // Common function to populate hashes for debrid services
    public func populateDebridIA(_ resultMagnets: [Magnet]) async {
        let now = Date()

        // If a hash isn't found in the IA, update it
        // If the hash is expired, remove it and update it
        let sendMagnets = resultMagnets.filter { magnet in
            if let IAIndex = realDebrid.IAValues.firstIndex(where: { $0.magnet.hash == magnet.hash }), enabledDebrids.contains(.realDebrid) {
                if now.timeIntervalSince1970 > realDebrid.IAValues[IAIndex].expiryTimeStamp {
                    realDebrid.IAValues.remove(at: IAIndex)
                    return true
                } else {
                    return false
                }
            } else if let IAIndex = allDebrid.IAValues.firstIndex(where: { $0.magnet.hash == magnet.hash }), enabledDebrids.contains(.allDebrid) {
                if now.timeIntervalSince1970 > allDebrid.IAValues[IAIndex].expiryTimeStamp {
                    allDebrid.IAValues.remove(at: IAIndex)
                    return true
                } else {
                    return false
                }
            } else if let IAIndex = premiumize.IAValues.firstIndex(where: { $0.magnet.hash == magnet.hash }), enabledDebrids.contains(.premiumize) {
                if now.timeIntervalSince1970 > premiumize.IAValues[IAIndex].expiryTimeStamp {
                    premiumize.IAValues.remove(at: IAIndex)
                    return true
                } else {
                    return false
                }
            } else {
                return true
            }
        }

        // Don't exit the function if the API fetch errors
        if !sendMagnets.isEmpty {
            if enabledDebrids.contains(.realDebrid) {
                do {
                    try await realDebrid.instantAvailability(magnets: sendMagnets)
                } catch {
                    await sendDebridError(error, prefix: "RealDebrid IA fetch error")
                }
            }

            if enabledDebrids.contains(.allDebrid) {
                do {
                    try await allDebrid.instantAvailability(magnets: sendMagnets)
                } catch {
                    await sendDebridError(error, prefix: "AllDebrid IA fetch error")
                }
            }

            if enabledDebrids.contains(.premiumize) {
                do {
                    try await premiumize.instantAvailability(magnets: sendMagnets)
                } catch {
                    await sendDebridError(error, prefix: "Premiumize IA fetch error")
                }
            }
        }
    }

    // Common function to match a magnet hash with a provided debrid service
    public func matchMagnetHash(_ magnet: Magnet) -> IAStatus {
        guard let magnetHash = magnet.hash else {
            return .none
        }

        let selectedSource = debridSourceFromName()

        if let selectedSource,
           let match = selectedSource.IAValues.first(where: { magnetHash == $0.magnet.hash })
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

        switch selectedDebridId?.name {
        case .some("RealDebrid"):
            if let realDebridItem = realDebrid.IAValues.first(where: { magnetHash == $0.magnet.hash }) {
                selectedRealDebridItem = realDebridItem
                return true
            } else {
                logManager?.error("DebridManager: Could not find the associated RealDebrid entry for magnet hash \(magnetHash)")
                return false
            }
        case .some("AllDebrid"):
            if let allDebridItem = allDebrid.IAValues.first(where: { magnetHash == $0.magnet.hash }) {
                selectedAllDebridItem = allDebridItem
                return true
            } else {
                logManager?.error("DebridManager: Could not find the associated AllDebrid entry for magnet hash \(magnetHash)")
                return false
            }
        case .some("Premiumize"):
            if let premiumizeItem = premiumize.IAValues.first(where: { magnetHash == $0.magnet.hash }) {
                selectedPremiumizeItem = premiumizeItem
                return true
            } else {
                logManager?.error("DebridManager: Could not find the associated Premiumize entry for magnet hash \(magnetHash)")
                return false
            }
        default:
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
                throw RealDebrid.RDError.AuthQuery(description: "The verification URL was invalid")
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
                throw AllDebrid.ADError.AuthQuery(description: "The PIN URL was invalid")
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
                throw Premiumize.PMError.AuthQuery(description: "OAuth callback Error: \(error)")
            }

            if let callbackUrl = url {
                try premiumize.handleAuthCallback(url: callbackUrl)
                completeDebridAuth(.premiumize, success: true)
            } else {
                throw Premiumize.PMError.AuthQuery(description: "The callback URL was invalid")
            }
        } catch {
            await sendDebridError(error, prefix: "Premiumize authentication error (callback)")

            completeDebridAuth(.premiumize, success: false)
        }
    }

    // MARK: - Logout UI linked functions

    // Common function to delegate what debrid service to logout of
    public func logoutDebrid(debridType: DebridType) async {
        switch debridType {
        case .realDebrid:
            await logoutRd()
        case .allDebrid:
            logoutAd()
        case .premiumize:
            logoutPm()
        }

        // Automatically resets the preferred debrid service if it was set to the logged out service
        if selectedDebridType == debridType {
            selectedDebridType = nil
        }
    }

    private func logoutRd() async {
        await realDebrid.logout()
        enabledDebrids.remove(.realDebrid)
    }

    private func logoutAd() {
        allDebrid.logout()
        enabledDebrids.remove(.allDebrid)

        logManager?.info(
            "AllDebrid: Logged out, API key needs to be removed",
            description: "Please manually delete the AllDebrid API key"
        )
    }

    private func logoutPm() {
        premiumize.logout()
        enabledDebrids.remove(.premiumize)
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

        switch selectedDebridType {
        case .realDebrid:
            await fetchRdDownload(magnet: magnet, cloudInfo: cloudInfo)
        case .allDebrid:
            await fetchAdDownload(magnet: magnet, cloudInfo: cloudInfo)
        case .premiumize:
            await fetchPmDownload(magnet: magnet, cloudInfo: cloudInfo)
        case .none:
            break
        }
    }

    func fetchRdDownload(magnet: Magnet?, cloudInfo: String?) async {
        do {
            if let magnet {
                let downloadLink = try await realDebrid.getDownloadLink(
                    magnet: magnet, ia: selectedRealDebridItem, iaFile: selectedRealDebridFile
                )

                // Update the UI
                downloadUrl = downloadLink
            } else {
                throw RealDebrid.RDError.FailedRequest(description: "Could not fetch your file from RealDebrid's cache or API")
            }

            // Fetch one more time to add updated data into the RD cloud cache
            await fetchRdCloud(bypassTTL: true)
        } catch {
            switch error {
            case RealDebrid.RDError.EmptyTorrents:
                showDeleteAlert.toggle()
            default:
                await sendDebridError(error, prefix: "RealDebrid download error", cancelString: "Download cancelled")

                if let torrentId = selectedRealDebridID {
                    try? await realDebrid.deleteTorrent(torrentId: torrentId)
                }
            }

            logManager?.hideIndeterminateToast()
        }
    }

    public func fetchDebridCloud(bypassTTL: Bool = false) async {
        switch selectedDebridType {
        case .realDebrid:
            await fetchRdCloud(bypassTTL: bypassTTL)
        case .allDebrid:
            await fetchAdCloud(bypassTTL: bypassTTL)
        case .premiumize:
            await fetchPmCloud(bypassTTL: bypassTTL)
        case .none:
            return
        }
    }

    // Refreshes torrents and downloads from a RD user's account
    public func fetchRdCloud(bypassTTL: Bool = false) async {
        if bypassTTL || Date().timeIntervalSince1970 > realDebridCloudTTL {
            do {
                realDebridCloudTorrents = try await realDebrid.getUserTorrents()
                realDebridCloudDownloads = try await realDebrid.getUserDownloads()

                // 5 minutes
                realDebridCloudTTL = Date().timeIntervalSince1970 + 300
            } catch {
                await sendDebridError(error, prefix: "RealDebrid cloud fetch error")
            }
        }
    }

    func deleteRdDownload(downloadID: String) async {
        do {
            try await realDebrid.deleteDownload(downloadId: downloadID)

            // Bypass TTL to get current RD values
            await fetchRdCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "RealDebrid download delete error")
        }
    }

    func deleteRdTorrent(torrentID: String? = nil, presentError: Bool = true) async {
        do {
            if let torrentID {
                try await realDebrid.deleteTorrent(torrentId: torrentID)

                await fetchRdCloud(bypassTTL: true)
            } else {
                throw RealDebrid.RDError.FailedRequest(description: "No torrent ID was provided")
            }
        } catch {
            await sendDebridError(error, prefix: "RealDebrid torrent delete error", presentError: presentError)
        }
    }

    func checkRdUserDownloads(userTorrentLink: String) async -> String? {
        do {
            let existingLinks = realDebridCloudDownloads.first { $0.link == userTorrentLink }
            if let existingLink = existingLinks?.fileName {
                return existingLink
            } else {
                return try await realDebrid.unrestrictLink(debridDownloadLink: userTorrentLink)
            }
        } catch {
            await sendDebridError(error, prefix: "RealDebrid download check error")

            return nil
        }
    }

    func fetchAdDownload(magnet: Magnet?, cloudInfo: String?) async {
        do {
            if let magnet {
                let downloadLink = try await allDebrid.getDownloadLink(
                    magnet: magnet, ia: selectedAllDebridItem, iaFile: selectedAllDebridFile
                )

                // Update UI
                downloadUrl = downloadLink
            } else {
                throw AllDebrid.ADError.FailedRequest(description: "Could not fetch your file from AllDebrid's cache or API")
            }

            // Fetch one more time to add updated data into the AD cloud cache
            await fetchAdCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "AllDebrid download error", cancelString: "Download cancelled")
        }
    }

    func checkAdUserLinks(lockedLink: String) async -> String? {
        do {
            let existingLinks = allDebridCloudLinks.first { $0.link == lockedLink }
            if let existingLink = existingLinks?.link {
                return existingLink
            } else {
                try await allDebrid.saveLink(link: lockedLink)
                return try await allDebrid.unlockLink(lockedLink: lockedLink)
            }
        } catch {
            await sendDebridError(error, prefix: "AllDebrid download check error")

            return nil
        }
    }

    // Refreshes torrents and downloads from a RD user's account
    public func fetchAdCloud(bypassTTL: Bool = false) async {
        if bypassTTL || Date().timeIntervalSince1970 > allDebridCloudTTL {
            do {
                allDebridCloudMagnets = try await allDebrid.getUserTorrents()
                allDebridCloudLinks = try await allDebrid.getUserDownloads()

                // 5 minutes
                allDebridCloudTTL = Date().timeIntervalSince1970 + 300
            } catch {
                await sendDebridError(error, prefix: "AlLDebrid cloud fetch error")
            }
        }
    }

    func deleteAdLink(link: String) async {
        do {
            try await allDebrid.deleteDownload(downloadId: link)

            await fetchAdCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "AllDebrid link delete error")
        }
    }

    func deleteAdMagnet(magnetId: String) async {
        do {
            try await allDebrid.deleteTorrent(torrentId: magnetId)

            await fetchAdCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "AllDebrid magnet delete error")
        }
    }

    func fetchPmDownload(magnet: Magnet?, cloudInfo: String? = nil) async {
        do {
            if let cloudInfo {
                downloadUrl = try await premiumize.checkUserDownloads(link: cloudInfo) ?? ""
                return
            }

            if let magnet {
                let downloadLink = try await premiumize.getDownloadLink(
                    magnet: magnet, ia: selectedPremiumizeItem, iaFile: selectedPremiumizeFile
                )

                downloadUrl = downloadLink
            } else {
                throw Premiumize.PMError.FailedRequest(description: "Could not fetch your file from Premiumize's cache or API")
            }

            // Fetch one more time to add updated data into the PM cloud cache
            await fetchPmCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "Premiumize download error", cancelString: "Download or transfer cancelled")
        }
    }

    // Refreshes items and fetches from a PM user account
    public func fetchPmCloud(bypassTTL: Bool = false) async {
        if bypassTTL || Date().timeIntervalSince1970 > premiumizeCloudTTL {
            do {
                let userItems = try await premiumize.getUserDownloads()
                withAnimation {
                    premiumizeCloudItems = userItems
                }

                // 5 minutes
                premiumizeCloudTTL = Date().timeIntervalSince1970 + 300
            } catch {
                let error = error as NSError
                if error.code != -999 {
                    await sendDebridError(error, prefix: "Premiumize cloud fetch error")
                }
            }
        }
    }

    public func deletePmItem(id: String) async {
        do {
            try await premiumize.deleteDownload(downloadId: id)

            // Bypass TTL to get current RD values
            await fetchPmCloud(bypassTTL: true)
        } catch {
            await sendDebridError(error, prefix: "Premiumize cloud delete error")
        }
    }
}
