//
//  AllDebridModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 11/25/22.
//

import Foundation

extension AllDebrid {
    // MARK: - Generic AllDebrid response

    // Uses a generic parametr for whatever underlying response is present
    struct ADResponse<ADData: Codable>: Codable {
        let status: String
        let data: ADData
    }

    // MARK: - PinResponse

    struct PinResponse: Codable {
        let pin, check: String
        let expiresIn: Int
        let userURL, baseURL, checkURL: String

        enum CodingKeys: String, CodingKey {
            case pin, check
            case expiresIn = "expires_in"
            case userURL = "user_url"
            case baseURL = "base_url"
            case checkURL = "check_url"
        }
    }

    // MARK: - ApiKeyResponse

    struct ApiKeyResponse: Codable {
        let apikey: String
        let activated: Bool
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case apikey, activated
            case expiresIn = "expires_in"
        }
    }

    // MARK: - AddMagnetResponse

    struct AddMagnetResponse: Codable {
        let magnets: [AddMagnetData]
    }

    // MARK: - AddMagnetData

    struct AddMagnetData: Codable {
        let magnet, hash, name, filenameOriginal: String
        let size: Int
        let ready: Bool
        let id: Int

        enum CodingKeys: String, CodingKey {
            case magnet, hash, name
            case filenameOriginal = "filename_original"
            case size, ready, id
        }
    }

    // MARK: - MagnetStatusResponse

    struct MagnetStatusResponse: Codable {
        let magnets: [MagnetStatusData]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let data = try? container.decode(MagnetStatusData.self, forKey: .magnets) {
                magnets = [data]
            } else if let data = try? container.decode([MagnetStatusData].self, forKey: .magnets) {
                magnets = data
            } else {
                magnets = []
            }
        }
    }

    // MARK: - MagnetStatusData

    struct MagnetStatusData: Codable {
        let id: Int
        let filename: String
        let size: Int
        let hash, status: String
        let statusCode, downloaded, uploaded, seeders: Int
        let downloadSpeed, processingPerc, uploadSpeed, uploadDate: Int
        let completionDate: Int
        let links: [MagnetStatusLink]
        let type: String
        let notified: Bool
        let version: Int
    }

    // MARK: - MagnetStatusLink

    // Abridged for required parameters
    struct MagnetStatusLink: Codable {
        let link: String
        let filename: String
        let size: Int
    }

    // MARK: - UnlockLinkResponse

    // Abridged for required parameters
    struct UnlockLinkResponse: Codable {
        let link: String
    }

    // MARK: - SavedLinksResponse

    struct SavedLinksResponse: Codable {
        let links: [SavedLink]
    }

    struct SavedLink: Codable, Hashable {
        let link: String
        let date: Int
        let filename: String
        let size: Int
    }

    // MARK: - InstantAvailabilityResponse

    struct InstantAvailabilityResponse: Codable {
        let magnets: [InstantAvailabilityMagnet]
    }

    // MARK: - IAMagnetResponse

    struct InstantAvailabilityMagnet: Codable {
        let magnet, hash: String
        let instant: Bool
        let files: [InstantAvailabilityFile]?
    }

    // MARK: - IAFileResponse

    struct InstantAvailabilityFile: Codable {
        let name: String

        enum CodingKeys: String, CodingKey {
            case name = "n"
        }
    }
}
