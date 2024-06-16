//
//  DebridModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/2/24.
//

import Foundation

struct DebridIA: Hashable, Sendable {
    let magnet: Magnet
    let expiryTimeStamp: Double
    var files: [DebridIAFile]
}

struct DebridIAFile: Hashable, Sendable {
    let id: Int
    let name: String
    let streamUrlString: String?
    let batchIds: [Int]

    init(id: Int, name: String, streamUrlString: String? = nil, batchIds: [Int] = []) {
        self.id = id
        self.name = name
        self.streamUrlString = streamUrlString
        self.batchIds = batchIds
    }
}

struct DebridCloudDownload: Hashable, Sendable {
    let id: String
    let fileName: String
    let link: String
}

struct DebridCloudMagnet: Hashable, Sendable {
    let id: String
    let fileName: String
    let status: String
    let hash: String
    let links: [String]
}

enum DebridError: Error {
    case InvalidUrl
    case InvalidPostBody
    case InvalidResponse
    case InvalidToken
    case EmptyData
    case EmptyUserMagnets
    case IsCaching
    case FailedRequest(description: String)
    case AuthQuery(description: String)
    case NotImplemented
}
