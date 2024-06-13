//
//  TorBoxWrapper.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/11/24.
//

import Foundation

// Torrents: /torrents/mylist
// IA: /torrents/checkcached
// Add Magnet: /torrents/createtorrent
// Delete torrent: /torrents/controltorrent
// Unrestrict: /torrents/requestdl

class TorBox: DebridSource, ObservableObject {
    var id: String = "TorBox"
    var abbreviation: String = "TB"
    var website: String = "https://torbox.app"

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
    @Published var cloudTorrents: [DebridCloudTorrent] = []
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

        let availableHashes = iaObjects.map {
            DebridIA(
                magnet: Magnet(hash: $0.hash, link: nil),
                source: self.id,
                expiryTimeStamp: Date().timeIntervalSince1970 + 300,
                files: []
            )
        }

        IAValues += availableHashes
    }

    // MARK: - Downloading

    func getRestrictedFile(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> (restrictedFile: DebridIAFile?, newIA: DebridIA?) {
        let torrentId = try await createTorrent(magnet: magnet)
        let torrentList = try await myTorrentList()
        guard let filteredTorrent = torrentList.first(where: { $0.id == torrentId }) else {
            throw DebridError.FailedRequest(description: "A torrent wasn't found. Are you sure it's cached?")
        }

        // If the torrent isn't saved, it's considered as caching
        guard filteredTorrent.downloadState == "cached" || filteredTorrent.downloadState == "completed" else {
            throw DebridError.IsCaching
        }

        if filteredTorrent.files.count > 1 {
            var copiedIA = ia

            copiedIA?.files = filteredTorrent.files.map { torrentFile in
                DebridIAFile(
                    fileId: torrentFile.id,
                    name: torrentFile.shortName,
                    streamUrlString: String(torrentId)
                )
            }

            return (nil, copiedIA)
        } else if let torrentFile = filteredTorrent.files.first {
            let restrictedFile = DebridIAFile(fileId: torrentFile.id, name: torrentFile.name, streamUrlString: String(torrentId))

            return (restrictedFile, nil)
        } else {
            return (nil, nil)
        }
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
            URLQueryItem(name: "file_id", value: String(restrictedFile.fileId))
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
    func getUserDownloads() async throws {}

    func checkUserDownloads(link: String) async throws -> String? {
        nil
    }

    func deleteDownload(downloadId: String) async throws {}

    func getUserTorrents() async throws {
        let torrentList = try await myTorrentList()
        cloudTorrents = torrentList.map { torrent in

            // Only need one link to force a green badge
            DebridCloudTorrent(
                torrentId: String(torrent.id),
                source: self.id,
                fileName: torrent.name,
                status: torrent.downloadState == "cached" || torrent.downloadState == "completed" ? "downloaded" : torrent.downloadState,
                hash: torrent.hash,
                links: [String(torrent.id)]
            )
        }
    }

    func deleteTorrent(torrentId: String?) async throws {
        guard let torrentId else {
            throw DebridError.InvalidPostBody
        }

        var request = URLRequest(url: URL(string: "\(baseApiUrl)/torrents/controltorrent")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ControlTorrentRequest(torrentId: torrentId, operation: "Delete")
        request.httpBody = try jsonEncoder.encode(body)

        try await performRequest(request: &request, requestName: "controltorrent")
    }
}
