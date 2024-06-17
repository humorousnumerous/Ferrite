//
//  OffCloudModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/12/24.
//

import Foundation

extension OffCloud {
    struct ErrorResponse: Codable, Sendable {
        let error: String
    }

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

    enum CloudExploreResponse: Codable {
        case links([String])
        case error(ErrorResponse)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            // Only continue if the data is a List which indicates a success
            if let linkArray = try? container.decode([String].self) {
                self = .links(linkArray)
            } else {
                let value = try container.decode(ErrorResponse.self)
                self = .error(value)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .links(array):
                try container.encode(array)
            case let .error(value):
                try container.encode(value)
            }
        }
    }

    struct CloudHistoryResponse: Codable, Sendable {
        let requestId: String
        let fileName: String
        let status: String
        let originalLink: String
        let isDirectory: Bool
        let server: String
    }
}
