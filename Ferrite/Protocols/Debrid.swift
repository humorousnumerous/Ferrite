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
    var description: String? { get }
    var cachedStatus: [String] { get }

    // Auth variables
    var authProcessing: Bool { get set }
    var isLoggedIn: Bool { get }

    // Manual API key
    var manualToken: String? { get }

    // Instant availability variables
    var IAValues: [DebridIA] { get set }

    // Cloud variables
    var cloudDownloads: [DebridCloudDownload] { get set }
    var cloudMagnets: [DebridCloudMagnet] { get set }
    var cloudTTL: Double { get set }

    // Common authentication functions
    func setApiKey(_ key: String)
    func logout() async

    // Instant availability functions
    func instantAvailability(magnets: [Magnet]) async throws

    // Fetches a download link from a source
    // Include the instant availability information with the args
    // Cloud magnets also checked here
    func getRestrictedFile(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> (restrictedFile: DebridIAFile?, newIA: DebridIA?)

    // Unrestricts a locked file
    func unrestrictFile(_ restrictedFile: DebridIAFile) async throws -> String

    // User downloads functions
    func getUserDownloads() async throws
    func checkUserDownloads(link: String) async throws -> String?
    func deleteUserDownload(downloadId: String) async throws

    // User magnet functions
    func getUserMagnets() async throws
    func deleteUserMagnet(cloudMagnetId: String?) async throws
}

extension DebridSource {
    var description: String? {
        nil
    }

    var cachedStatus: [String] {
        []
    }
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
