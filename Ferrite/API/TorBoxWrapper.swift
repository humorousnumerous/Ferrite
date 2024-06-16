//
//  TorBoxWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/11/24.
//

import Foundation

class TorBox: DebridSource, ObservableObject {
    let id = "TorBox"
    let abbreviation = "TB"
    let website = "https://torbox.app"
    let description: String? = "TorBox is a debrid service that is used for downloads and media playback with seeding. " +
        "Both free and paid plans are available."

    @Published var authProcessing: Bool = false
    var isLoggedIn: Bool {
        getToken() != nil
    }

    var manualToken: String? {
        if UserDefaults.standard.bool(forKey: "TorBox.UseManualKey") {
            return getToken()
        } else {
            return nil
        }
    }

    @Published var IAValues: [DebridIA] = []
    @Published var cloudDownloads: [DebridCloudDownload] = []
    @Published var cloudMagnets: [DebridCloudMagnet] = []
    var cloudTTL: Double = 0.0

    private let baseApiUrl = "https://api.torbox.app/v1/api"
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    // MARK: - Auth

    func setApiKey(_ key: String) {
        FerriteKeychain.shared.set(key, forKey: "TorBox.ApiKey")
        UserDefaults.standard.set(true, forKey: "TorBox.UseManualKey")
    }

    func logout() async {
        FerriteKeychain.shared.delete("TorBox.ApiKey")
        UserDefaults.standard.removeObject(forKey: "TorBox.UseManualKey")
    }

    private func getToken() -> String? {
        FerriteKeychain.shared.get("TorBox.ApiKey")
    }

    // MARK: - Common request

    // Wrapper request function which matches the responses and returns data
    @discardableResult private func performRequest(request: inout URLRequest, requestName: String) async throws -> Data {
        guard let token = getToken() else {
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
            throw DebridError.FailedRequest(description: "The request \(requestName) failed because you were unauthorized. Please relogin to TorBox in Settings.")
        } else {
            throw DebridError.FailedRequest(description: "The request \(requestName) failed with status code \(response.statusCode).")
        }
    }

    // MARK: - Instant availability

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

        var components = URLComponents(string: "\(baseApiUrl)/torrents/checkcached")!
        components.queryItems = sendMagnets.map { URLQueryItem(name: "hash", value: $0.hash) }
        components.queryItems?.append(URLQueryItem(name: "format", value: "list"))
        components.queryItems?.append(URLQueryItem(name: "list_files", value: "true"))

        guard let url = components.url else {
            throw DebridError.InvalidUrl
        }

        var request = URLRequest(url: url)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(TBResponse<InstantAvailabilityData>.self, from: data)

        // If the data is a failure, return
        guard case let .links(iaObjects) = rawResponse.data else {
            return
        }

        let availableHashes = iaObjects.map { iaObject in
            DebridIA(
                magnet: Magnet(hash: iaObject.hash, link: nil),
                expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                files: iaObject.files.enumerated().compactMap { index, iaFile in
                    guard let fileName = iaFile.name.split(separator: "/").last else {
                        return nil
                    }

                    return DebridIAFile(
                        id: index,
                        name: String(fileName)
                    )
                }
            )
        }

        IAValues += availableHashes
    }

    // MARK: - Downloading

    func getRestrictedFile(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> (restrictedFile: DebridIAFile?, newIA: DebridIA?) {
        let cloudMagnetId = try await createTorrent(magnet: magnet)
        let cloudMagnetList = try await myTorrentList()
        guard let filteredCloudMagnet = cloudMagnetList.first(where: { $0.id == cloudMagnetId }) else {
            throw DebridError.FailedRequest(description: "Could not find a cached magnet. Are you sure it's cached?")
        }

        // If the user magnet isn't saved, it's considered as caching
        guard filteredCloudMagnet.downloadState == "cached" || filteredCloudMagnet.downloadState == "completed" else {
            throw DebridError.IsCaching
        }

        guard let cloudMagnetFile = filteredCloudMagnet.files[safe: iaFile?.id ?? 0] else {
            throw DebridError.EmptyUserMagnets
        }

        let restrictedFile = DebridIAFile(id: cloudMagnetFile.id, name: cloudMagnetFile.name, streamUrlString: String(cloudMagnetId))
        return (restrictedFile, nil)
    }

    private func createTorrent(magnet: Magnet) async throws -> Int {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/createtorrent")!)
        request.httpMethod = "POST"

        guard let magnetLink = magnet.link else {
            throw DebridError.EmptyData
        }

        let formData = FormDataBody(params: ["magnet": magnetLink])
        request.setValue("multipart/form-data; boundary=\(formData.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.body

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(TBResponse<CreateTorrentResponse>.self, from: data)

        guard let torrentId = rawResponse.data?.torrentId else {
            throw DebridError.EmptyData
        }

        return torrentId
    }

    private func myTorrentList() async throws -> [MyTorrentListResponse] {
        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/mylist")!)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(TBResponse<[MyTorrentListResponse]>.self, from: data)

        guard let torrentList = rawResponse.data else {
            throw DebridError.EmptyData
        }

        return torrentList
    }

    func unrestrictFile(_ restrictedFile: DebridIAFile) async throws -> String {
        var components = URLComponents(string: "\(baseApiUrl)/torrents/requestdl")!
        components.queryItems = [
            URLQueryItem(name: "token", value: getToken()),
            URLQueryItem(name: "torrent_id", value: restrictedFile.streamUrlString),
            URLQueryItem(name: "file_id", value: String(restrictedFile.id))
        ]

        guard let url = components.url else {
            throw DebridError.InvalidUrl
        }

        var request = URLRequest(url: url)

        let data = try await performRequest(request: &request, requestName: #function)
        let rawResponse = try jsonDecoder.decode(TBResponse<RequestDLResponse>.self, from: data)

        guard let unrestrictedLink = rawResponse.data else {
            throw DebridError.FailedRequest(description: "Could not get an unrestricted URL from TorBox.")
        }

        return unrestrictedLink
    }

    // MARK: - Cloud methods

    // Unused
    func getUserDownloads() {}

    func checkUserDownloads(link: String) -> String? {
        link
    }

    func deleteUserDownload(downloadId: String) {}

    func getUserMagnets() async throws {
        let cloudMagnetList = try await myTorrentList()
        cloudMagnets = cloudMagnetList.map { cloudMagnet in

            // Only need one link to force a green badge
            DebridCloudMagnet(
                id: String(cloudMagnet.id),
                fileName: cloudMagnet.name,
                status: cloudMagnet.downloadState == "cached" || cloudMagnet.downloadState == "completed" ? "downloaded" : cloudMagnet.downloadState,
                hash: cloudMagnet.hash,
                links: cloudMagnet.files.map { String($0.id) }
            )
        }
    }

    func deleteUserMagnet(cloudMagnetId: String?) async throws {
        guard let cloudMagnetId else {
            throw DebridError.InvalidPostBody
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/controltorrent")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ControlTorrentRequest(torrentId: cloudMagnetId, operation: "Delete")
        request.httpBody = try jsonEncoder.encode(body)

        try await performRequest(request: &request, requestName: "controltorrent")
    }
}
