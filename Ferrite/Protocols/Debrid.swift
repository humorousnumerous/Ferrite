//
//  Debrid.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/1/24.
//

import Foundation

public protocol DebridSource {
    // ID of the service
    var id: String { get }
    var abbreviation: String { get }
    var website: String { get }

    // Auth variables
    var authProcessing: Bool { get set }
    var isLoggedIn: Bool { get }

    // Common authentication functions
    func setApiKey(_ key: String) -> Bool
    func logout() async

    // Instant availability variables
    var IAValues: [DebridIA] { get set }

    // Instant availability functions
    func instantAvailability(magnets: [Magnet]) async throws

    // Fetches a download link from a source
    // Include the instant availability information with the args
    // Torrents also checked here
    func getDownloadLink(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> String

    // Cloud variables
    var cloudDownloads: [DebridCloudDownload] { get set }
    var cloudTorrents: [DebridCloudTorrent] { get set }

    // User downloads functions
    func getUserDownloads() async throws -> [DebridCloudDownload]
    func checkUserDownloads(link: String) async throws -> String?
    func deleteDownload(downloadId: String) async throws

    // User torrent functions
    func getUserTorrents() async throws -> [DebridCloudTorrent]
    func deleteTorrent(torrentId: String) async throws
}

public protocol PollingDebridSource: DebridSource {
    // Task reference for polling
    var authTask: Task<Void, Error>? { get set }

    // Fetches the Auth URL
    func getAuthUrl() async throws -> URL
}

public protocol OAuthDebridSource: DebridSource {
    // Fetches the auth URL
    func getAuthUrl() throws -> URL

    // Handles an OAuth callback
    func handleAuthCallback(url: URL) throws
}
