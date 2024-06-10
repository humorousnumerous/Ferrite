//
//  PremiumizeWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 11/28/22.
//

import Foundation

public class Premiumize: OAuthDebridSource, ObservableObject {
    public let id = "Premiumize"
    public let abbreviation = "PM"
    public let website = "https://premiumize.me"
    @Published public var authProcessing: Bool = false
    public var isLoggedIn: Bool {
        getToken() != nil
    }

    public var manualToken: String? {
        if UserDefaults.standard.bool(forKey: "Premiumize.UseManualKey") {
            return getToken()
        } else {
            return nil
        }
    }

    @Published public var IAValues: [DebridIA] = []
    @Published public var cloudDownloads: [DebridCloudDownload] = []
    @Published public var cloudTorrents: [DebridCloudTorrent] = []
    public var cloudTTL: Double = 0.0

    let baseAuthUrl = "https://www.premiumize.me/authorize"
    let baseApiUrl = "https://www.premiumize.me/api"
    let clientId = "791565696"

    let jsonDecoder = JSONDecoder()

    // MARK: - Auth

    public func getAuthUrl() throws -> URL {
        var urlComponents = URLComponents(string: baseAuthUrl)!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]

        if let url = urlComponents.url {
            return url
        } else {
            throw DebridError.InvalidUrl
        }
    }

    public func handleAuthCallback(url: URL) throws {
        let callbackComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)

        guard let callbackFragment = callbackComponents?.fragment else {
            throw DebridError.InvalidResponse
        }

        var fragmentComponents = URLComponents()
        fragmentComponents.query = callbackFragment

        guard let accessToken = fragmentComponents.queryItems?.first(where: { $0.name == "access_token" })?.value else {
            throw DebridError.InvalidToken
        }

        FerriteKeychain.shared.set(accessToken, forKey: "Premiumize.AccessToken")
    }

    // Adds a manual API key instead of web auth
    public func setApiKey(_ key: String) {
        FerriteKeychain.shared.set(key, forKey: "Premiumize.AccessToken")
        UserDefaults.standard.set(true, forKey: "Premiumize.UseManualKey")
    }

    public func getToken() -> String? {
        FerriteKeychain.shared.get("Premiumize.AccessToken")
    }

    // Clears tokens. No endpoint to deregister a device
    public func logout() {
        FerriteKeychain.shared.delete("Premiumize.AccessToken")
        UserDefaults.standard.removeObject(forKey: "Premiumize.UseManualKey")
    }

    // MARK: - Common request

    // Wrapper request function which matches the responses and returns data
    @discardableResult private func performRequest(request: inout URLRequest, requestName: String) async throws -> Data {
        guard let token = getToken() else {
            throw DebridError.InvalidToken
        }

        // Use the API query parameter if a manual API key is present
        if UserDefaults.standard.bool(forKey: "Premiumize.UseManualKey") {
            guard
                let requestUrl = request.url,
                var components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false)
            else {
                throw DebridError.InvalidUrl
            }

            let apiTokenItem = URLQueryItem(name: "apikey", value: token)

            if components.queryItems == nil {
                components.queryItems = [apiTokenItem]
            } else {
                components.queryItems?.append(apiTokenItem)
            }

            request.url = components.url
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw DebridError.FailedRequest(description: "No HTTP response given")
        }

        if response.statusCode >= 200, response.statusCode <= 299 {
            return data
        } else if response.statusCode == 401 {
            throw DebridError.FailedRequest(description: "The request \(requestName) failed because you were unauthorized. Please relogin to Premiumize in Settings.")
        } else {
            throw DebridError.FailedRequest(description: "The request \(requestName) failed with status code \(response.statusCode).")
        }
    }

    // MARK: - Instant availability

    public func instantAvailability(magnets: [Magnet]) async throws {
        let now = Date().timeIntervalSince1970

        // Remove magnets that don't have an associated link for PM along with existing TTL logic
        let sendMagnets = magnets.filter { magnet in
            if magnet.link == nil {
                return false
            }

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

        let availableMagnets = try await divideCacheRequests(magnets: sendMagnets)

        // Split DDL requests into chunks of 10
        for chunk in availableMagnets.chunked(into: 10) {
            let tempIA = try await divideDDLRequests(magnetChunk: chunk)
            IAValues += tempIA
        }
    }

    // Function to divide and execute DDL endpoint requests in parallel
    // Calls this for 10 requests at a time to not overwhelm API servers
    public func divideDDLRequests(magnetChunk: [Magnet]) async throws -> [DebridIA] {
        let tempIA = try await withThrowingTaskGroup(of: DebridIA.self) { group in
            for magnet in magnetChunk {
                group.addTask {
                    try await self.fetchDDL(magnet: magnet)
                }
            }

            var chunkedIA: [DebridIA] = []
            for try await ia in group {
                chunkedIA.append(ia)
            }
            return chunkedIA
        }

        return tempIA
    }

    // Grabs DDL links
    func fetchDDL(magnet: Magnet) async throws -> DebridIA {
        if magnet.hash == nil {
            throw DebridError.EmptyData
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/transfer/directdl")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "src", value: magnet.link)]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(DDLResponse.self, from: data)
        let content = rawResponse.content ?? []

        if !content.isEmpty {
            let files = content.map { file in
                DebridIAFile(
                    fileId: 0,
                    name: file.path.split(separator: "/").last.flatMap { String($0) } ?? file.path,
                    streamUrlString: file.link
                )
            }

            return DebridIA(
                magnet: magnet,
                source: id,
                expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                files: files
            )
        } else {
            throw DebridError.EmptyData
        }
    }

    // Function to divide and execute cache endpoint requests in parallel
    // Calls this for 100 hashes at a time due to API limits
    public func divideCacheRequests(magnets: [Magnet]) async throws -> [Magnet] {
        let availableMagnets = try await withThrowingTaskGroup(of: [Magnet].self) { group in
            for chunk in magnets.chunked(into: 100) {
                group.addTask {
                    try await self.checkCache(magnets: chunk)
                }
            }

            var chunkedMagnets: [Magnet] = []
            for try await magnetArray in group {
                chunkedMagnets += magnetArray
            }

            return chunkedMagnets
        }

        return availableMagnets
    }

    // Parent function for initial checking of the cache
    func checkCache(magnets: [Magnet]) async throws -> [Magnet] {
        var urlComponents = URLComponents(string: "\(baseApiUrl)/cache/check")!
        urlComponents.queryItems = magnets.map { URLQueryItem(name: "items[]", value: $0.hash) }
        guard let url = urlComponents.url else {
            throw DebridError.InvalidUrl
        }

        var request = URLRequest(url: url)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(CacheCheckResponse.self, from: data)

        if rawResponse.response.isEmpty {
            throw DebridError.EmptyData
        } else {
            let availableMagnets = magnets.enumerated().compactMap { index, magnet in
                if rawResponse.response[safe: index] == true {
                    return magnet
                } else {
                    return nil
                }
            }

            return availableMagnets
        }
    }

    // MARK: - Downloading

    // Wrapper function to fetch a DDL link from the API
    public func getDownloadLink(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> String {
        // Store the item in PM cloud for later use
        try await createTransfer(magnet: magnet)

        if let iaFile, let streamUrlString = iaFile.streamUrlString {
            return streamUrlString
        } else if let premiumizeItem = ia, let firstFile = premiumizeItem.files[safe: 0], let streamUrlString = firstFile.streamUrlString {
            return streamUrlString
        } else {
            throw DebridError.FailedRequest(description: "Could not fetch your file from the Premiumize API")
        }
    }

    func createTransfer(magnet: Magnet) async throws {
        guard let magnetLink = magnet.link else {
            throw DebridError.FailedRequest(description: "The magnet link is invalid")
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/transfer/create")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "src", value: magnetLink)]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        try await performRequest(request: &request, requestName: #function)
    }

    // MARK: - Cloud methods

    public func getUserDownloads() async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/item/listall")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(AllItemsResponse.self, from: data)

        if rawResponse.files.isEmpty {
            throw DebridError.EmptyData
        }

        // The "link" is the ID for Premiumize
        cloudDownloads = rawResponse.files.map { file in
            DebridCloudDownload(downloadId: file.id, source: self.id, fileName: file.name, link: file.id)
        }
    }

    func itemDetails(itemID: String) async throws -> ItemDetailsResponse {
        var urlComponents = URLComponents(string: "\(baseApiUrl)/item/details")!
        urlComponents.queryItems = [URLQueryItem(name: "id", value: itemID)]
        guard let url = urlComponents.url else {
            throw DebridError.InvalidUrl
        }

        var request = URLRequest(url: url)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(ItemDetailsResponse.self, from: data)

        return rawResponse
    }

    public func checkUserDownloads(link: String) async throws -> String? {
        // Link is the cloud item ID
        try await itemDetails(itemID: link).link
    }

    public func deleteDownload(downloadId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/item/delete")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "id", value: downloadId)]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        try await performRequest(request: &request, requestName: #function)
    }

    // No user torrents for Premiumize
    public func getUserTorrents() async throws {}

    public func deleteTorrent(torrentId: String?) async throws {}
}
