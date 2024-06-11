//
//  SourceModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/24/22.
//

import Foundation

enum ApiCredentialResponseType: String, Codable, Hashable, Sendable {
    case json
    case text
}

struct SourceJson: Codable, Hashable, Sendable, PluginJson {
    let name: String
    let version: Int16
    let minVersion: String?
    let about: String?
    let website: String?
    let dynamicWebsite: Bool?
    let fallbackUrls: [String]?
    let trackers: [String]?
    let api: SourceApiJson?
    let jsonParser: SourceJsonParserJson?
    let rssParser: SourceRssParserJson?
    let htmlParser: SourceHtmlParserJson?
    let author: String?
    let listId: UUID?
    let listName: String?
    let tags: [PluginTagJson]?
}

extension SourceJson {
    // Fetches all tags without optional requirement
    func getTags() -> [PluginTagJson] {
        tags ?? []
    }
}

enum SourcePreferredParser: Int16, CaseIterable, Sendable {
    // case none = 0
    case scraping = 1
    case rss = 2
    case siteApi = 3
}

struct SourceApiJson: Codable, Hashable, Sendable {
    let apiUrl: String?
    let clientId: SourceApiCredentialJson?
    let clientSecret: SourceApiCredentialJson?
}

struct SourceApiCredentialJson: Codable, Hashable, Sendable {
    let query: String?
    let value: String?
    let dynamic: Bool?
    let url: String?
    let responseType: ApiCredentialResponseType?
    let expiryLength: Double?
}

struct SourceJsonParserJson: Codable, Hashable, Sendable {
    let searchUrl: String
    let request: SourceRequestJson?
    let results: String?
    let subResults: String?
    let title: SourceComplexQueryJson
    let magnetHash: SourceComplexQueryJson?
    let magnetLink: SourceComplexQueryJson?
    let subName: SourceComplexQueryJson?
    let size: SourceComplexQueryJson?
    let sl: SourceSLJson?
}

struct SourceRssParserJson: Codable, Hashable, Sendable {
    let rssUrl: String?
    let searchUrl: String
    let request: SourceRequestJson?
    let items: String
    let title: SourceComplexQueryJson
    let magnetHash: SourceComplexQueryJson?
    let magnetLink: SourceComplexQueryJson?
    let subName: SourceComplexQueryJson?
    let size: SourceComplexQueryJson?
    let sl: SourceSLJson?
}

struct SourceHtmlParserJson: Codable, Hashable, Sendable {
    let searchUrl: String?
    let request: SourceRequestJson?
    let rows: String
    let title: SourceComplexQueryJson
    let magnet: SourceMagnetJson
    let subName: SourceComplexQueryJson?
    let size: SourceComplexQueryJson?
    let sl: SourceSLJson?
}

struct SourceComplexQueryJson: Codable, Hashable, Sendable {
    let query: String
    let discriminator: String?
    let attribute: String?
    let regex: String?
}

struct SourceMagnetJson: Codable, Hashable, Sendable {
    let query: String
    let attribute: String
    let regex: String?
    let externalLinkQuery: String?
}

struct SourceSLJson: Codable, Hashable, Sendable {
    let seeders: String?
    let leechers: String?
    let combined: String?
    let attribute: String?
    let discriminator: String?
    let seederRegex: String?
    let leecherRegex: String?
}

struct SourceRequestJson: Codable, Hashable, Sendable {
    let method: String?
    let headers: [String: String]?
    let body: String?
}
