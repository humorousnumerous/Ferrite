//
//  DebridModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/2/24.
//

import Foundation

public struct DebridIA: Sendable, Hashable {
    let magnet: Magnet
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

public struct DebridCloudFile {}
