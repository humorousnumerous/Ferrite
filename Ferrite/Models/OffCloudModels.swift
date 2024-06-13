//
//  OffCloudModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/12/24.
//

import Foundation

extension OffCloud {
    struct InstantAvailabilityRequest: Codable, Sendable {
        let hashes: [String]
    }

    struct InstantAvailabilityResponse: Codable, Sendable {
        let cachedItems: [String]
    }

    struct CloudDownloadRequest: Codable, Sendable {
        let url: String
    }

    struct CloudDownloadResponse: Codable, Sendable {
        let requestId: String
        let fileName: String
        let status: String
        let originalLink: String
        let url: String
    }

    typealias CloudExploreResponse = [String]

    struct CloudHistoryResponse: Codable, Sendable {
        let requestId: String
        let fileName: String
        let status: String
        let originalLink: String
        let isDirectory: Bool
        let server: String
    }
}
