//
//  TorBoxModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/11/24.
//

import Foundation

extension TorBox {
    struct TBResponse<TBData: Codable>: Codable {
        let success: Bool
        let detail: String
        let data: TBData?
    }

    // MARK: - InstantAvailability

    enum InstantAvailabilityData: Codable {
        case links([InstantAvailabilityDataObject])
        case failure(InstantAvailabilityDataFailure)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            // Only continue if the data is a List which indicates a success
            if let linkArray = try? container.decode([InstantAvailabilityDataObject].self) {
                self = .links(linkArray)
            } else {
                let value = try container.decode(InstantAvailabilityDataFailure.self)
                self = .failure(value)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .links(array):
                try container.encode(array)
            case let .failure(value):
                try container.encode(value)
            }
        }
    }

    struct InstantAvailabilityDataObject: Codable, Sendable {
        let name: String
        let size: Int
        let hash: String
        let files: [InstantAvailabilityFile]
    }

    struct InstantAvailabilityFile: Codable, Sendable {
        let name: String
        let size: Int
    }

    struct InstantAvailabilityDataFailure: Codable, Sendable {
        let data: Bool
    }

    struct CreateTorrentResponse: Codable, Sendable {
        let hash: String
        let torrentId: Int
        let authId: String

        enum CodingKeys: String, CodingKey {
            case hash
            case torrentId = "torrent_id"
            case authId = "auth_id"
        }
    }

    struct MyTorrentListResponse: Codable, Sendable {
        let id: Int
        let hash: String
        let name: String
        let downloadState: String
        let files: [MyTorrentListFile]

        enum CodingKeys: String, CodingKey {
            case id, hash, name, files
            case downloadState = "download_state"
        }
    }

    struct MyTorrentListFile: Codable, Sendable {
        let id: Int
        let hash: String
        let name: String
        let shortName: String

        enum CodingKeys: String, CodingKey {
            case id, hash, name
            case shortName = "short_name"
        }
    }

    typealias RequestDLResponse = String

    struct ControlTorrentRequest: Codable, Sendable {
        let torrentId: String
        let operation: String

        enum CodingKeys: String, CodingKey {
            case operation
            case torrentId = "torrent_id"
        }
    }
}
