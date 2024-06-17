//
//  RealDebridWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/7/22.
//

import Foundation

class RealDebrid: PollingDebridSource, ObservableObject {
    let id = "RealDebrid"
    let abbreviation = "RD"
    let website = "https://real-debrid.com"
    let cachedStatus: [String] = ["downloaded"]
    var authTask: Task<Void, Error>?

    @Published var authProcessing: Bool = false

    // Check the manual token since getTokens() is async
    var isLoggedIn: Bool {
        FerriteKeychain.shared.get("RealDebrid.AccessToken") != nil
    }

    var manualToken: String? {
        if UserDefaults.standard.bool(forKey: "RealDebrid.UseManualKey") {
            return FerriteKeychain.shared.get("RealDebrid.AccessToken")
        } else {
            return nil
        }
    }

    @Published var IAValues: [DebridIA] = []
    @Published var cloudDownloads: [DebridCloudDownload] = []
    @Published var cloudMagnets: [DebridCloudMagnet] = []
    var cloudTTL: Double = 0.0

    private let baseAuthUrl = "https://api.real-debrid.com/oauth/v2"
    private let baseApiUrl = "https://api.real-debrid.com/rest/1.0"
    private let openSourceClientId = "X245A4XAIBGVM"

    private let jsonDecoder = JSONDecoder()

    @MainActor
    private func setUserDefaultsValue(_ value: Any, forKey: String) {
        UserDefaults.standard.set(value, forKey: forKey)
    }

    @MainActor
    private func removeUserDefaultsValue(forKey: String) {
        UserDefaults.standard.removeObject(forKey: forKey)
    }

    init() {
        // Populate user downloads and magnets
        Task {
            try? await getUserDownloads()
            try? await getUserMagnets()
        }
    }

    // MARK: - Auth

    // Fetches the device code from RD
    func getAuthUrl() async throws -> URL {
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
    func getDeviceCredentials(deviceCode: String) async throws {
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
    func getApiTokens(deviceCode: String) async throws {
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

    func getToken() async -> String? {
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
    func setApiKey(_ key: String) {
        FerriteKeychain.shared.set(key, forKey: "RealDebrid.AccessToken")
        FerriteKeychain.shared.delete("RealDebrid.RefreshToken")
        FerriteKeychain.shared.delete("RealDebrid.AccessTokenStamp")

        UserDefaults.standard.set(true, forKey: "RealDebrid.UseManualKey")
    }

    // Deletes tokens from device and RD's servers
    func logout() async {
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
            throw DebridError.FailedRequest(description: "The request \(requestName) failed because you were unauthorized. Please relogin to RealDebrid in Settings.")
        } else {
            throw DebridError.FailedRequest(description: "The request \(requestName) failed with status code \(response.statusCode).")
        }
    }

    // MARK: - Instant availability

    // Checks if the magnet is streamable on RD
    func instantAvailability(magnets: [Magnet]) async throws {
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

        let rawResponseDict = try jsonDecoder.decode([String: InstantAvailabilityResponse].self, from: data)

        for (hash, response) in rawResponseDict {
            guard let data = response.data else {
                continue
            }

            if data.rd.isEmpty {
                continue
            }

            // Handle files array
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
                    if !files.contains(where: { $0.id == batchFile.id }) {
                        files.append(
                            DebridIAFile(
                                id: batchFile.id,
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
                    expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                    files: files
                )
            )
        }
    }

    // MARK: - Downloading

    // Wrapper function to fetch a download link from the API
    func getRestrictedFile(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> (restrictedFile: DebridIAFile?, newIA: DebridIA?) {
        var selectedMagnetId = ""

        do {
            // Don't queue a new job if the magnet already exists in the user's library
            if let existingCloudMagnet = cloudMagnets.first(where: { $0.hash == magnet.hash && $0.status == "downloaded" }) {
                selectedMagnetId = existingCloudMagnet.id
            } else {
                selectedMagnetId = try await addMagnet(magnet: magnet)

                try await selectFiles(debridID: selectedMagnetId, fileIds: iaFile?.batchIds ?? [])
            }

            // RealDebrid has 1 as the first ID for a file
            let restrictedFile = try await torrentInfo(
                debridID: selectedMagnetId,
                selectedFileId: iaFile?.id ?? 1
            )

            return (restrictedFile, nil)
        } catch {
            if case DebridError.EmptyUserMagnets = error, !selectedMagnetId.isEmpty {
                try? await deleteUserMagnet(cloudMagnetId: selectedMagnetId)
            }

            // Re-raise the error to the calling function
            throw error
        }
    }

    // Adds a magnet link to the user's RD account
    func addMagnet(magnet: Magnet) async throws -> String {
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
    func selectFiles(debridID: String, fileIds: [Int]) async throws {
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
    func torrentInfo(debridID: String, selectedFileId: Int?) async throws -> DebridIAFile {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/info/\(debridID)")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(TorrentInfoResponse.self, from: data)
        let filteredFiles = rawResponse.files.filter { $0.selected == 1 }
        let linkIndex = filteredFiles.firstIndex(where: { $0.id == selectedFileId })

        // Let the user know if a magnet is downloading
        if let cloudMagnetLink = rawResponse.links[safe: linkIndex ?? -1], rawResponse.status == "downloaded" {
            return DebridIAFile(
                id: 0,
                name: rawResponse.filename,
                streamUrlString: cloudMagnetLink
            )
        } else if rawResponse.status == "downloading" || rawResponse.status == "queued" {
            throw DebridError.IsCaching
        } else {
            throw DebridError.EmptyUserMagnets
        }
    }

    // Downloads link from selectFiles for playback
    func unrestrictFile(_ restrictedFile: DebridIAFile) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/unrestrict/link")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "link", value: restrictedFile.streamUrlString)]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(UnrestrictLinkResponse.self, from: data)

        return rawResponse.download
    }

    // MARK: - Cloud methods

    // Gets the user's cloud magnet library
    func getUserMagnets() async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode([UserTorrentsResponse].self, from: data)
        cloudMagnets = rawResponse.map { response in
            DebridCloudMagnet(
                id: response.id,
                fileName: response.filename,
                status: response.status,
                hash: response.hash,
                links: response.links
            )
        }
    }

    // Deletes a magnet download from RD
    func deleteUserMagnet(cloudMagnetId: String?) async throws {
        let deleteId: String

        if let cloudMagnetId {
            deleteId = cloudMagnetId
        } else {
            // Refresh the user magnet list
            // The first file is the currently caching one
            let _ = try await getUserMagnets()
            guard let firstCloudMagnet = cloudMagnets[safe: -1] else {
                throw DebridError.EmptyUserMagnets
            }

            deleteId = firstCloudMagnet.id
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/delete/\(deleteId)")!)
        request.httpMethod = "DELETE"

        try await performRequest(request: &request, requestName: #function)
    }

    // Gets the user's downloads
    func getUserDownloads() async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/downloads")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode([UserDownloadsResponse].self, from: data)
        cloudDownloads = rawResponse.map { response in
            DebridCloudDownload(id: response.id, fileName: response.filename, link: response.download)
        }
    }

    // Not used
    func checkUserDownloads(link: String) -> String? {
        link
    }

    func deleteUserDownload(downloadId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/downloads/delete/\(downloadId)")!)
        request.httpMethod = "DELETE"

        try await performRequest(request: &request, requestName: #function)
    }
}
