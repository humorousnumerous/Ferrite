//
//  RealDebridWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/7/22.
//

import Foundation

public class RealDebrid: PollingDebridSource, ObservableObject {    
    public let id = "RealDebrid"
    public let abbreviation = "RD"
    public let website = "https://real-debrid.com"
    public var authTask: Task<Void, Error>?

    @Published public var authProcessing: Bool = false

    // Directly checked because the request fetch uses async
    public var isLoggedIn: Bool {
        FerriteKeychain.shared.get("RealDebrid.AccessToken") != nil
    }

    @Published public var IAValues: [DebridIA] = []
    @Published public var cloudDownloads: [DebridCloudDownload] = []
    @Published public var cloudTorrents: [DebridCloudTorrent] = []
    public var cloudTTL: Double = 0.0

    let baseAuthUrl = "https://api.real-debrid.com/oauth/v2"
    let baseApiUrl = "https://api.real-debrid.com/rest/1.0"
    let openSourceClientId = "X245A4XAIBGVM"

    let jsonDecoder = JSONDecoder()

    @MainActor
    func setUserDefaultsValue(_ value: Any, forKey: String) {
        UserDefaults.standard.set(value, forKey: forKey)
    }

    @MainActor
    func removeUserDefaultsValue(forKey: String) {
        UserDefaults.standard.removeObject(forKey: forKey)
    }

    // MARK: - Auth

    // Fetches the device code from RD
    public func getAuthUrl() async throws -> URL {
        var urlComponents = URLComponents(string: "\(baseAuthUrl)/device/code")!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: openSourceClientId),
            URLQueryItem(name: "new_credentials", value: "yes")
        ]

        guard let url = urlComponents.url else {
            throw DebridError.InvalidUrl
        }

        let request = URLRequest(url: url)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Validate the URL before doing anything else
            let rawResponse = try jsonDecoder.decode(DeviceCodeResponse.self, from: data)
            guard let directVerificationUrl = URL(string: rawResponse.directVerificationURL) else {
                throw DebridError.AuthQuery(description: "The verification URL is invalid")
            }

            // Spawn the polling task separately
            authTask = Task {
                try await getDeviceCredentials(deviceCode: rawResponse.deviceCode)
            }

            return directVerificationUrl
        } catch {
            print("Couldn't get the new client creds!")
            throw DebridError.AuthQuery(description: error.localizedDescription)
        }
    }

    // Fetches the user's client ID and secret
    public func getDeviceCredentials(deviceCode: String) async throws {
        var urlComponents = URLComponents(string: "\(baseAuthUrl)/device/credentials")!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: openSourceClientId),
            URLQueryItem(name: "code", value: deviceCode)
        ]

        guard let url = urlComponents.url else {
            throw DebridError.InvalidUrl
        }

        let request = URLRequest(url: url)

        // Timer to poll RD API for credentials
        var count = 0

        while count < 12 {
            if Task.isCancelled {
                throw DebridError.AuthQuery(description: "Token request cancelled.")
            }

            let (data, _) = try await URLSession.shared.data(for: request)

            // We don't care if this fails
            let rawResponse = try? jsonDecoder.decode(DeviceCredentialsResponse.self, from: data)

            // If there's a client ID from the response, end the task successfully
            if let clientId = rawResponse?.clientID, let clientSecret = rawResponse?.clientSecret {
                await setUserDefaultsValue(clientId, forKey: "RealDebrid.ClientId")
                FerriteKeychain.shared.set(clientSecret, forKey: "RealDebrid.ClientSecret")

                try await getApiTokens(deviceCode: deviceCode)

                return
            } else {
                try await Task.sleep(seconds: 5)
                count += 1
            }
        }

        throw DebridError.AuthQuery(description: "Could not fetch the client ID and secret in time. Try logging in again.")
    }

    // Fetch all tokens for the user and store in FerriteKeychain.shared
    public func getApiTokens(deviceCode: String) async throws {
        guard let clientId = UserDefaults.standard.string(forKey: "RealDebrid.ClientId") else {
            throw DebridError.EmptyData
        }

        guard let clientSecret = FerriteKeychain.shared.get("RealDebrid.ClientSecret") else {
            throw DebridError.EmptyData
        }

        var request = URLRequest(url: URL(string: "\(baseAuthUrl)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: deviceCode),
            URLQueryItem(name: "grant_type", value: "http://oauth.net/grant_type/device/1.0")
        ]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        let rawResponse = try jsonDecoder.decode(TokenResponse.self, from: data)

        FerriteKeychain.shared.set(rawResponse.accessToken, forKey: "RealDebrid.AccessToken")
        FerriteKeychain.shared.set(rawResponse.refreshToken, forKey: "RealDebrid.RefreshToken")

        let accessTimestamp = Date().timeIntervalSince1970 + Double(rawResponse.expiresIn)
        await setUserDefaultsValue(accessTimestamp, forKey: "RealDebrid.AccessTokenStamp")
    }

    public func getToken() async -> String? {
        let accessTokenStamp = UserDefaults.standard.double(forKey: "RealDebrid.AccessTokenStamp")

        if Date().timeIntervalSince1970 > accessTokenStamp {
            do {
                if let refreshToken = FerriteKeychain.shared.get("RealDebrid.RefreshToken") {
                    try await getApiTokens(deviceCode: refreshToken)
                }
            } catch {
                print(error)
                return nil
            }
        }

        return FerriteKeychain.shared.get("RealDebrid.AccessToken")
    }

    // Adds a manual API key instead of web auth
    // Clear out existing refresh tokens and timestamps
    public func setApiKey(_ key: String) -> Bool {
        FerriteKeychain.shared.set(key, forKey: "RealDebrid.AccessToken")
        FerriteKeychain.shared.delete("RealDebrid.RefreshToken")
        FerriteKeychain.shared.delete("RealDebrid.AccessTokenStamp")

        UserDefaults.standard.set(true, forKey: "RealDebrid.UseManualKey")

        return FerriteKeychain.shared.get("RealDebrid.AccessToken") == key
    }

    // Deletes tokens from device and RD's servers
    public func logout() async {
        FerriteKeychain.shared.delete("RealDebrid.RefreshToken")
        FerriteKeychain.shared.delete("RealDebrid.ClientSecret")
        await removeUserDefaultsValue(forKey: "RealDebrid.ClientId")
        await removeUserDefaultsValue(forKey: "RealDebrid.AccessTokenStamp")

        // Run the request, doesn't matter if it fails
        if let token = FerriteKeychain.shared.get("RealDebrid.AccessToken") {
            var request = URLRequest(url: URL(string: "\(baseApiUrl)/disable_access_token")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)

            FerriteKeychain.shared.delete("RealDebrid.AccessToken")
            await removeUserDefaultsValue(forKey: "RealDebrid.UseManualKey")
        }
    }

    // MARK: - Common request

    // Wrapper request function which matches the responses and returns data
    @discardableResult private func performRequest(request: inout URLRequest, requestName: String) async throws -> Data {
        guard let token = await getToken() else {
            throw DebridError.InvalidToken
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw DebridError.FailedRequest(description: "No HTTP response given")
        }

        if response.statusCode >= 200, response.statusCode <= 299 {
            return data
        } else if response.statusCode == 401 {
            await logout()
            throw DebridError.FailedRequest(description: "The request \(requestName) failed because you were unauthorized. Please relogin to RealDebrid in Settings.")
        } else {
            throw DebridError.FailedRequest(description: "The request \(requestName) failed with status code \(response.statusCode).")
        }
    }

    // MARK: - Instant availability

    // Checks if the magnet is streamable on RD
    public func instantAvailability(magnets: [Magnet]) async throws {
        let now = Date().timeIntervalSince1970

        let sendMagnets = magnets.filter { magnet in
            if let IAIndex = IAValues.firstIndex(where: { $0.magnet.hash == magnet.hash }) {
                if now > IAValues[IAIndex].expiryTimeStamp {
                    IAValues.remove(at: IAIndex)
                    return true
                } else {
                    return false
                }
            } else {
                return true
            }
        }

        if sendMagnets.isEmpty {
            return
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/instantAvailability/\(sendMagnets.compactMap(\.hash).joined(separator: "/"))")!)

        let data = try await performRequest(request: &request, requestName: #function)

        // Does not account for torrent packs at the moment
        let rawResponseDict = try jsonDecoder.decode([String: InstantAvailabilityResponse].self, from: data)

        for (hash, response) in rawResponseDict {
            guard let data = response.data else {
                continue
            }

            if data.rd.isEmpty {
                continue
            }

            // Is this a batch?
            if data.rd.count > 1 || data.rd[0].count > 1 {
                // Batch array
                let batches = data.rd.map { fileDict in
                    let batchFiles: [RealDebrid.IABatchFile] = fileDict.map { key, value in
                        // Force unwrapped ID. Is safe because ID is guaranteed on a successful response
                        RealDebrid.IABatchFile(id: Int(key)!, fileName: value.filename)
                    }.sorted(by: { $0.id < $1.id })

                    return RealDebrid.IABatch(files: batchFiles)
                }

                var files: [DebridIAFile] = []

                for batch in batches {
                    let batchFileIds = batch.files.map(\.id)

                    for batchFile in batch.files {
                        if !files.contains(where: { $0.fileId == batchFile.id }) {
                            files.append(
                                DebridIAFile(
                                    fileId: batchFile.id,
                                    name: batchFile.fileName,
                                    batchIds: batchFileIds
                                )
                            )
                        }
                    }
                }

                // TTL: 5 minutes
                IAValues.append(
                    DebridIA(
                        magnet: Magnet(hash: hash, link: nil),
                        source: id,
                        expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                        files: files
                    )
                )
            } else {
                IAValues.append(
                    DebridIA(
                        magnet: Magnet(hash: hash, link: nil),
                        source: id,
                        expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                        files: []
                    )
                )
            }
        }
    }

    // MARK: - Downloading

    // Wrapper function to fetch a download link from the API
    public func getDownloadLink(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> String {
        var selectedMagnetId = ""

        do {
            // Don't queue a new job if the torrent already exists
            if let existingTorrent = cloudTorrents.first(where: { $0.hash == magnet.hash && $0.status == "downloaded" }) {
                selectedMagnetId = existingTorrent.torrentId
            } else {
                selectedMagnetId = try await addMagnet(magnet: magnet)

                try await selectFiles(debridID: selectedMagnetId, fileIds: iaFile?.batchIds ?? [])
            }

            // RealDebrid has 1 as the first ID for a file
            let torrentLink = try await torrentInfo(
                debridID: selectedMagnetId,
                selectedFileId: iaFile?.fileId ?? 1
            )
            let downloadLink = try await unrestrictLink(debridDownloadLink: torrentLink)

            return downloadLink
        } catch {
            if case DebridError.EmptyTorrents = error, !selectedMagnetId.isEmpty {
                try? await deleteTorrent(torrentId: selectedMagnetId)
            }

            // Re-raise the error to the calling function
            throw error
        }
    }

    // Adds a magnet link to the user's RD account
    public func addMagnet(magnet: Magnet) async throws -> String {
        guard let magnetLink = magnet.link else {
            throw DebridError.FailedRequest(description: "The magnet link is invalid")
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/addMagnet")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "magnet", value: magnetLink)]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(AddMagnetResponse.self, from: data)

        return rawResponse.id
    }

    // Queues the magnet link for downloading
    public func selectFiles(debridID: String, fileIds: [Int]) async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/selectFiles/\(debridID)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()

        if fileIds.isEmpty {
            bodyComponents.queryItems = [URLQueryItem(name: "files", value: "all")]
        } else {
            let joinedIds = fileIds.map(String.init).joined(separator: ",")
            bodyComponents.queryItems = [URLQueryItem(name: "files", value: joinedIds)]
        }

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        try await performRequest(request: &request, requestName: #function)
    }

    // Gets the info of a torrent from a given ID
    public func torrentInfo(debridID: String, selectedFileId: Int?) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/info/\(debridID)")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(TorrentInfoResponse.self, from: data)
        let filteredFiles = rawResponse.files.filter { $0.selected == 1 }
        let linkIndex = filteredFiles.firstIndex(where: { $0.id == selectedFileId })

        // Let the user know if a torrent is downloading
        if let torrentLink = rawResponse.links[safe: linkIndex ?? -1], rawResponse.status == "downloaded" {
            return torrentLink
        } else if rawResponse.status == "downloading" || rawResponse.status == "queued" {
            throw DebridError.IsCaching
        } else {
            throw DebridError.EmptyTorrents
        }
    }

    // Downloads link from selectFiles for playback
    public func unrestrictLink(debridDownloadLink: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/unrestrict/link")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "link", value: debridDownloadLink)]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(UnrestrictLinkResponse.self, from: data)

        return rawResponse.download
    }

    // MARK: - Cloud methods

    // Gets the user's torrent library
    public func getUserTorrents() async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode([UserTorrentsResponse].self, from: data)
        cloudTorrents = rawResponse.map { response in
            DebridCloudTorrent(
                torrentId: response.id,
                source: self.id,
                fileName: response.filename,
                status: response.status,
                hash: response.hash,
                links: response.links
            )
        }
    }

    // Deletes a torrent download from RD
    public func deleteTorrent(torrentId: String?) async throws {
        let deleteId: String

        if let torrentId {
            deleteId = torrentId
        } else {
            // Refresh the torrent cloud
            // The first file is the currently caching one
            let _ = try await getUserTorrents()
            guard let firstTorrent = cloudTorrents[safe: -1] else {
                throw DebridError.EmptyTorrents
            }

            deleteId = firstTorrent.torrentId
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/delete/\(deleteId)")!)
        request.httpMethod = "DELETE"

        try await performRequest(request: &request, requestName: #function)
    }

    // Gets the user's downloads
    public func getUserDownloads() async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/downloads")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode([UserDownloadsResponse].self, from: data)
        cloudDownloads = rawResponse.map { response in
            DebridCloudDownload(downloadId: response.id, source: self.id, fileName: response.filename, link: response.download)
        }
    }

    // Not used
    public func checkUserDownloads(link: String) -> String? {
        nil
    }

    public func deleteDownload(downloadId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/downloads/delete/\(downloadId)")!)
        request.httpMethod = "DELETE"

        try await performRequest(request: &request, requestName: #function)
    }
}
