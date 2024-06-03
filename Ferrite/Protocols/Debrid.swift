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

    // Common authentication functions
    func setApiKey(_ key: String) -> Bool
    func logout() async

    // Fetches a download link from a source
    // Include the instant availability information with the args
    func getDownloadLink(magnet: Magnet, ia: DebridIA?, iaFile: DebridIAFile?) async throws -> String
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
