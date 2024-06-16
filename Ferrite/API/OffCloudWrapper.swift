//
//  OffCloudWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/12/24.
//

import Foundation

class OffCloud: DebridSource, ObservableObject {
    let id = "OffCloud"
    let abbreviation = "OC"
    let website = "https://offcloud.com"
    let description: String? = "OffCloud is a debrid service that is used for downloads and media playback. " +
        "You must pay to access this service. \n\n" +
        "This service does not inform if a magnet link is a batch before downloading."

    @Published var authProcessing: Bool = false
    var isLoggedIn: Bool {
        getToken() != nil
    }

    var manualToken: String? {
        if UserDefaults.standard.bool(forKey: "OffCloud.UseManualKey") {
            return getToken()
        } else {
            return nil
        }
    }

    @Published var IAValues: [DebridIA] = []
    @Published var cloudDownloads: [DebridCloudDownload] = []
    @Published var cloudMagnets: [DebridCloudMagnet] = []
    var cloudTTL: Double = 0.0

    private let baseApiUrl = "https://offcloud.com/api"
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    func setApiKey(_ key: String) {
        FerriteKeychain.shared.set(key, forKey: "OffCloud.ApiKey")
        UserDefaults.standard.set(true, forKey: "OffCloud.UseManualKey")
    }

    func logout() async {
        FerriteKeychain.shared.delete("OffCloud.ApiKey")
        UserDefaults.standard.removeObject(forKey: "OffCloud.UseManualKey")
    }

    private func getToken() -> String? {
        FerriteKeychain.shared.get("OffCloud.ApiKey")
    }

    // Wrapper request function which matches the responses and returns data
    @discardableResult private func performRequest(request: inout URLRequest, requestName: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw DebridError.FailedRequest(description: "No HTTP response given")
        }

        if response.statusCode >= 200, response.statusCode <= 299 {
            return data
        } else if response.statusCode == 401 {
            throw DebridError.FailedRequest(description: "The request \(requestName) failed because you were unauthorized. Please relogin to TorBox in Settings.")
        } else {
            print(response)
            throw DebridError.FailedRequest(description: "The request \(requestName) failed with status code \(response.statusCode).")
        }
    }

    // Builds a URL for further requests
    private func buildRequestURL(urlString: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: urlString) else {
            throw DebridError.InvalidUrl
        }

        guard let token = getToken() else {
            throw DebridError.InvalidToken
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: token)
        ] + queryItems

        if let url = components.url {
            return url
        } else {
            throw DebridError.InvalidUrl
        }
    }

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

        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/cache"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = InstantAvailabilityRequest(hashes: sendMagnets.compactMap(\.hash))
        request.httpBody = try jsonEncoder.encode(body)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(InstantAvailabilityResponse.self, from: data)

        let availableHashes = rawResponse.cachedItems.map {
            DebridIA(
                magnet: Magnet(hash: $0, link: nil),
                source: self.id,
                expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                files: []
            )
        }

        IAValues += availableHashes
    }

    // Cloud in OffCloud's API
    func getRestrictedFile(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> (restrictedFile: DebridIAFile?, newIA: DebridIA?) {
        let selectedMagnet: DebridCloudMagnet

        // Don't queue a new job if the magnet already exists in the user's account
        if let existingCloudMagnet = cloudMagnets.first(where: { $0.hash == magnet.hash && $0.status == "downloaded" }) {
            selectedMagnet = existingCloudMagnet
        } else {
            let cloudDownloadResponse = try await offcloudDownload(magnet: magnet)

            guard cloudDownloadResponse.status == "downloaded" else {
                throw DebridError.IsCaching
            }

            selectedMagnet = DebridCloudMagnet(
                cloudMagnetId: cloudDownloadResponse.requestId,
                source: id,
                fileName: cloudDownloadResponse.fileName,
                status: cloudDownloadResponse.status,
                hash: "",
                links: []
            )
        }

        let cloudExploreLinks = try await cloudExplore(requestId: selectedMagnet.cloudMagnetId)

        if cloudExploreLinks.count > 1 {
            var copiedIA = ia

            copiedIA?.files = cloudExploreLinks.enumerated().compactMap { index, exploreLink in
                guard let exploreURL = URL(string: exploreLink) else {
                    return nil
                }

                return DebridIAFile(
                    fileId: index,
                    name: exploreURL.lastPathComponent,
                    streamUrlString: exploreLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                )
            }

            return (nil, copiedIA)
        } else if let exploreLink = cloudExploreLinks.first {
            let restrictedFile = DebridIAFile(
                fileId: 0,
                name: selectedMagnet.fileName,
                streamUrlString: exploreLink
            )

            return (restrictedFile, nil)
        } else {
            return (nil, nil)
        }
    }

    // Called as "cloud" in offcloud's API
    private func offcloudDownload(magnet: Magnet) async throws -> CloudDownloadResponse {
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/cloud"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let magnetLink = magnet.link else {
            throw DebridError.EmptyData
        }

        let body = CloudDownloadRequest(url: magnetLink)
        request.httpBody = try jsonEncoder.encode(body)

        let data = try await performRequest(request: &request, requestName: "cloud")
        let rawResponse = try jsonDecoder.decode(CloudDownloadResponse.self, from: data)

        return rawResponse
    }

    private func cloudExplore(requestId: String) async throws -> CloudExploreResponse {
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/cloud/explore/\(requestId)"))

        let data = try await performRequest(request: &request, requestName: "cloudExplore")
        let rawResponse = try jsonDecoder.decode(CloudExploreResponse.self, from: data)

        return rawResponse
    }

    func unrestrictFile(_ restrictedFile: DebridIAFile) async throws -> String {
        guard let streamUrlString = restrictedFile.streamUrlString else {
            throw DebridError.FailedRequest(description: "Could not get a streaming URL from the OffCloud API")
        }

        return streamUrlString
    }

    func getUserDownloads() {}

    func checkUserDownloads(link: String) -> String? {
        link
    }

    func deleteUserDownload(downloadId: String) {}

    func getUserMagnets() async throws {
        var request = URLRequest(url: try buildRequestURL(urlString: "\(baseApiUrl)/cloud/history"))

        let data = try await performRequest(request: &request, requestName: "cloudHistory")
        let rawResponse = try jsonDecoder.decode([CloudHistoryResponse].self, from: data)

        cloudMagnets = rawResponse.compactMap { cloudHistory in
            guard let magnetHash = Magnet(hash: nil, link: cloudHistory.originalLink).hash else {
                return nil
            }

            return DebridCloudMagnet(
                cloudMagnetId: cloudHistory.requestId,
                source: self.id,
                fileName: cloudHistory.fileName,
                status: cloudHistory.status,
                hash: magnetHash,
                links: [cloudHistory.originalLink]
            )
        }
    }

    // Uses the base website because this isn't present in the API path but still works like the API?
    func deleteUserMagnet(cloudMagnetId: String?) async throws {
        guard let cloudMagnetId else {
            throw DebridError.InvalidPostBody
        }

        var request = URLRequest(url: try buildRequestURL(urlString: "\(website)/cloud/remove/\(cloudMagnetId)"))
        try await performRequest(request: &request, requestName: "cloudRemove")
    }
}
