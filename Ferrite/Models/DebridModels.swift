//
//  DebridModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/2/24.
//

import Foundation

public struct DebridIA: Hashable, Sendable {
    let magnet: Magnet
    let source: String
    let expiryTimeStamp: Double
    var files: [DebridIAFile]
}

public struct DebridIAFile: Hashable, Sendable {
    let fileId: Int
    let name: String
    let streamUrlString: String?
    let batchIds: [Int]

    init(fileId: Int, name: String, streamUrlString: String? = nil, batchIds: [Int] = []) {
        self.fileId = fileId
        self.name = name
        self.streamUrlString = streamUrlString
        self.batchIds = batchIds
    }
}

public struct DebridCloudDownload: Hashable, Sendable {
    let downloadId: String
    let source: String
    let fileName: String
    let link: String
}

public struct DebridCloudTorrent: Hashable, Sendable {
    let torrentId: String
    let source: String
    let fileName: String
    let status: String
    let hash: String
    let links: [String]
}

public enum DebridError: Error {
    case InvalidUrl
    case InvalidPostBody
    case InvalidResponse
    case InvalidToken
    case EmptyData
    case EmptyTorrents
    case IsCaching
    case FailedRequest(description: String)
    case AuthQuery(description: String)
}
