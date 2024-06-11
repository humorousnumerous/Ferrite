//
//  Debrid.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/1/24.
//

import Foundation

protocol DebridSource: AnyObservableObject {
    // ID of the service
    // var id: DebridInfo { get }
    var id: String { get }
    var abbreviation: String { get }
    var website: String { get }

    // Auth variables
    var authProcessing: Bool { get set }
    var isLoggedIn: Bool { get }

    // Manual API key
    var manualToken: String? { get }

    // Instant availability variables
    var IAValues: [DebridIA] { get set }

    // Cloud variables
    var cloudDownloads: [DebridCloudDownload] { get set }
    var cloudTorrents: [DebridCloudTorrent] { get set }
    var cloudTTL: Double { get set }

    // Common authentication functions
    func setApiKey(_ key: String)
    func logout() async

    // Instant availability functions
    func instantAvailability(magnets: [Magnet]) async throws

    // Fetches a download link from a source
    // Include the instant availability information with the args
    // Torrents also checked here
    func getDownloadLink(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> String

    // User downloads functions
    func getUserDownloads() async throws
    func checkUserDownloads(link: String) async throws -> String?
    func deleteDownload(downloadId: String) async throws

    // User torrent functions
    func getUserTorrents() async throws
    func deleteTorrent(torrentId: String?) async throws
}

protocol PollingDebridSource: DebridSource {
    // Task reference for polling
    var authTask: Task<Void, Error>? { get set }

    // Fetches the Auth URL
    func getAuthUrl() async throws -> URL
}

protocol OAuthDebridSource: DebridSource {
    // Fetches the auth URL
    func getAuthUrl() throws -> URL

    // Handles an OAuth callback
    func handleAuthCallback(url: URL) throws
}
