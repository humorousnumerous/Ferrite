//
//  AllDebridWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 11/25/22.
//

import Foundation

// TODO: Fix errors
public class AllDebrid: PollingDebridSource, ObservableObject {
    public let id = DebridInfo(
        name: "AllDebrid", abbreviation: "AD", website: "https://alldebrid.com"
    )
    public var authTask: Task<Void, Error>?

    public var authProcessing: Bool = false
    public var isLoggedIn: Bool {
        getToken() != nil
    }

    public var IAValues: [DebridIA] = []
    public var cloudDownloads: [DebridCloudDownload] = []
    public var cloudTorrents: [DebridCloudTorrent] = []

    let baseApiUrl = "https://api.alldebrid.com/v4"
    let appName = "Ferrite"

    let jsonDecoder = JSONDecoder()

    // MARK: - Auth

    // Fetches information for PIN auth
    public func getAuthUrl() async throws -> URL {
        let url = try buildRequestURL(urlString: "\(baseApiUrl)/pin/get")
        let request = URLRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Validate the URL before doing anything else
            let rawResponse = try jsonDecoder.decode(ADResponse<PinResponse>.self, from: data).data
            guard let userUrl = URL(string: rawResponse.userURL) else {
                throw ADError.AuthQuery(description: "The login URL is invalid")
            }

            // Spawn the polling task separately
            authTask = Task {
                try await getApiKey(checkID: rawResponse.check, pin: rawResponse.pin)
            }

            return userUrl
        } catch {
            print("Couldn't get pin information!")
            throw ADError.AuthQuery(description: error.localizedDescription)
        }
    }

    // Fetches API keys
    public func getApiKey(checkID: String, pin: String) async throws {
        let queryItems = [
            URLQueryItem(name: "agent", value: appName),
            URLQueryItem(name: "check", value: checkID),
            URLQueryItem(name: "pin", value: pin)
        ]

        let request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/pin/check", queryItems: queryItems))

        // Timer to poll AD API for key
        authTask = Task {
            var count = 0

            while count < 12 {
                if Task.isCancelled {
                    throw ADError.AuthQuery(description: "Token request cancelled.")
                }

                let (data, _) = try await URLSession.shared.data(for: request)

                // We don't care if this fails
                let rawResponse = try? self.jsonDecoder.decode(ADResponse<ApiKeyResponse>.self, from: data).data

                // If there's an API key from the response, end the task successfully
                if let apiKeyResponse = rawResponse {
                    FerriteKeychain.shared.set(apiKeyResponse.apikey, forKey: "AllDebrid.ApiKey")

                    return
                } else {
                    try await Task.sleep(seconds: 5)
                    count += 1
                }
            }

            throw ADError.AuthQuery(description: "Could not fetch the client ID and secret in time. Try logging in again.")
        }

        if case let .failure(error) = await authTask?.result {
            throw error
        }
    }

    // Adds a manual API key instead of web auth
    public func setApiKey(_ key: String) -> Bool {
        FerriteKeychain.shared.set(key, forKey: "AllDebrid.ApiKey")
        UserDefaults.standard.set(true, forKey: "AllDebrid.UseManualKey")

        return FerriteKeychain.shared.get("AllDebrid.ApiKey") == key
    }

    public func getToken() -> String? {
        FerriteKeychain.shared.get("AllDebrid.ApiKey")
    }

    // Clears tokens. No endpoint to deregister a device
    public func logout() {
        FerriteKeychain.shared.delete("AllDebrid.ApiKey")
        UserDefaults.standard.removeObject(forKey: "AllDebrid.UseManualKey")
    }

    // MARK: - Common request

    // Wrapper request function which matches the responses and returns data
    @discardableResult private func performRequest(request: inout URLRequest, requestName: String) async throws -> Data {
        guard let token = getToken() else {
            throw ADError.InvalidToken
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw ADError.FailedRequest(description: "No HTTP response given")
        }

        if response.statusCode >= 200, response.statusCode <= 299 {
            return data
        } else if response.statusCode == 401 {
            logout()
            throw ADError.FailedRequest(description: "The request \(requestName) failed because you were unauthorized. Please relogin to AllDebrid in Settings.")
        } else {
            throw ADError.FailedRequest(description: "The request \(requestName) failed with status code \(response.statusCode).")
        }
    }

    // Builds a URL for further requests
    private func buildRequestURL(urlString: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: urlString) else {
            throw ADError.InvalidUrl
        }

        components.queryItems = [
            URLQueryItem(name: "agent", value: appName)
        ] + queryItems

        if let url = components.url {
            return url
        } else {
            throw ADError.InvalidUrl
        }
    }

    // MARK: - Instant availability

    public func instantAvailability(magnets: [Magnet]) async throws {
        let queryItems = magnets.map { URLQueryItem(name: "magnets[]", value: $0.hash) }
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/magnet/instant", queryItems: queryItems))

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ADResponse<InstantAvailabilityResponse>.self, from: data).data

        let filteredMagnets = rawResponse.magnets.filter { $0.instant == true && $0.files != nil }
        let availableHashes = filteredMagnets.map { magnetResp in
            // Force unwrap is OK here since the filter caught any nil values
            let files = magnetResp.files!.enumerated().map { index, magnetFile in
                DebridIAFile(fileId: index, name: magnetFile.name)
            }

            return DebridIA(
                magnet: Magnet(hash: magnetResp.hash, link: magnetResp.magnet),
                source: self.id.name,
                expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                files: files
            )
        }

        IAValues += availableHashes
    }

    // MARK: - Downloading

    // Wrapper function to fetch a download link from the API
    public func getDownloadLink(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> String {
        let selectedMagnetId: String

        if let existingMagnet = cloudTorrents.first(where: { $0.hash == magnet.hash && $0.status == "Ready" }) {
            selectedMagnetId = existingMagnet.torrentId
        } else {
            let magnetId = try await addMagnet(magnet: magnet)
            selectedMagnetId = String(magnetId)
        }

        let lockedLink = try await fetchMagnetStatus(
            magnetId: selectedMagnetId,
            selectedIndex: iaFile?.fileId ?? 0
        )

        try await saveLink(link: lockedLink)
        let downloadUrl = try await unlockLink(lockedLink: lockedLink)

        return downloadUrl
    }

    // Adds a magnet link to the user's AD account
    public func addMagnet(magnet: Magnet) async throws -> Int {
        guard let magnetLink = magnet.link else {
            throw ADError.FailedRequest(description: "The magnet link is invalid")
        }

        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/magnet/upload"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "magnets[]", value: magnetLink)
        ]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ADResponse<AddMagnetResponse>.self, from: data).data

        if let magnet = rawResponse.magnets[safe: 0] {
            return magnet.id
        } else {
            throw ADError.InvalidResponse
        }
    }

    public func fetchMagnetStatus(magnetId: String, selectedIndex: Int?) async throws -> String {
        let queryItems = [
            URLQueryItem(name: "id", value: magnetId)
        ]
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/magnet/status", queryItems: queryItems))

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ADResponse<MagnetStatusResponse>.self, from: data).data

        // Better to fetch no link at all than the wrong link
        if let linkWrapper = rawResponse.magnets[safe: 0]?.links[safe: selectedIndex ?? -1] {
            return linkWrapper.link
        } else {
            throw ADError.EmptyTorrents
        }
    }

    public func unlockLink(lockedLink: String) async throws -> String {
        let queryItems = [
            URLQueryItem(name: "link", value: lockedLink)
        ]
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/link/unlock", queryItems: queryItems))

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ADResponse<UnlockLinkResponse>.self, from: data).data

        return rawResponse.link
    }

    public func saveLink(link: String) async throws {
        let queryItems = [
            URLQueryItem(name: "links[]", value: link)
        ]
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/user/links/save", queryItems: queryItems))

        try await performRequest(request: &request, requestName: #function)
    }

    // MARK: - Cloud methods

    // Referred to as "User magnets" in AllDebrid's API
    public func getUserTorrents() async throws -> [DebridCloudTorrent] {
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/magnet/status"))

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ADResponse<MagnetStatusResponse>.self, from: data).data

        if rawResponse.magnets.isEmpty {
            throw ADError.EmptyData
        }

        cloudTorrents = rawResponse.magnets.map { magnetResponse in
            DebridCloudTorrent(
                torrentId: String(magnetResponse.id),
                source: self.id.name,
                fileName: magnetResponse.filename,
                status: magnetResponse.status,
                hash: magnetResponse.hash,
                links: magnetResponse.links.map(\.link)
            )
        }

        return cloudTorrents
    }

    public func deleteTorrent(torrentId: String) async throws {
        let queryItems = [
            URLQueryItem(name: "id", value: torrentId)
        ]
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/magnet/delete", queryItems: queryItems))

        try await performRequest(request: &request, requestName: #function)
    }

    public func getUserDownloads() async throws -> [DebridCloudDownload] {
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/user/links"))

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ADResponse<SavedLinksResponse>.self, from: data).data

        if rawResponse.links.isEmpty {
            throw ADError.EmptyData
        }

        // The link is also the ID
        cloudDownloads = rawResponse.links.map { link in
            DebridCloudDownload(
                downloadId: link.link, source: self.id.name, fileName: link.filename, link: link.link
            )
        }

        return cloudDownloads
    }

    // Not used
    public func checkUserDownloads(link: String) async throws -> String? {
        nil
    }

    // The downloadId is actually the download link
    public func deleteDownload(downloadId: String) async throws {
        let queryItems = [
            URLQueryItem(name: "link", value: downloadId)
        ]
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/user/links/delete", queryItems: queryItems))

        try await performRequest(request: &request, requestName: #function)
    }
}
