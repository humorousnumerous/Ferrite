//
//  BackupManager.swift
//  Ferrite
//
//  Created by Brian Dashore on 9/16/22.
//

import Foundation

class BackupManager: ObservableObject {
    // Constant variable for backup versions
    private let latestBackupVersion: Int = 2

    var logManager: LoggingManager?

    @Published var showRestoreAlert = false
    @Published var showRestoreCompletedAlert = false
    @Published var restoreCompletedMessage: [String] = []

    @Published var backupUrls: [URL] = []
    @Published var selectedBackupUrl: URL?

    @MainActor
    private func updateRestoreCompletedMessage(newString: String) {
        restoreCompletedMessage.append(newString)
    }

    @MainActor
    private func toggleRestoreCompletedAlert() {
        showRestoreCompletedAlert.toggle()
    }

    @MainActor
    private func updateBackupUrls(newUrl: URL) {
        backupUrls.append(newUrl)
    }

    func createBackup() async {
        var backup = Backup(version: latestBackupVersion)
        let backgroundContext = PersistenceController.shared.backgroundContext

        let bookmarkRequest = Bookmark.fetchRequest()
        if let fetchedBookmarks = try? backgroundContext.fetch(bookmarkRequest) {
            backup.bookmarks = fetchedBookmarks.compactMap {
                BookmarkJson(
                    title: $0.title,
                    source: $0.source,
                    size: $0.size,
                    magnetLink: $0.magnetLink,
                    magnetHash: $0.magnetHash,
                    seeders: $0.seeders,
                    leechers: $0.leechers
                )
            }
        }

        let historyRequest = History.fetchRequest()
        if let fetchedHistory = try? backgroundContext.fetch(historyRequest) {
            backup.history = fetchedHistory.compactMap { history in
                if history.entries == nil {
                    return nil
                } else {
                    return HistoryJson(
                        dateString: history.dateString,
                        date: history.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                        entries: history.entryArray.compactMap { entry in
                            if let name = entry.name, let url = entry.url {
                                return HistoryEntryJson(
                                    name: name,
                                    subName: entry.subName,
                                    url: url,
                                    timeStamp: entry.timeStamp,
                                    source: entry.source
                                )
                            } else {
                                return nil
                            }
                        }
                    )
                }
            }
        }

        let sourceRequest = Source.fetchRequest()
        if let sources = try? backgroundContext.fetch(sourceRequest) {
            backup.sourceNames = sources.map(\.name)
        }

        let actionRequest = Action.fetchRequest()
        if let actions = try? backgroundContext.fetch(actionRequest) {
            backup.actionNames = actions.map(\.name)
        }

        let pluginListRequest = PluginList.fetchRequest()
        if let pluginLists = try? backgroundContext.fetch(pluginListRequest) {
            backup.pluginListUrls = pluginLists.map(\.urlString)
        }

        do {
            let encodedJson = try JSONEncoder().encode(backup)
            let backupsPath = FileManager.default.appDirectory.appendingPathComponent("Backups")
            if !FileManager.default.fileExists(atPath: backupsPath.path) {
                try FileManager.default.createDirectory(atPath: backupsPath.path, withIntermediateDirectories: true, attributes: nil)
            }

            let snapshot = Int(Date().timeIntervalSince1970.rounded())
            let writeUrl = backupsPath.appendingPathComponent("Ferrite-backup-\(snapshot).feb")

            try encodedJson.write(to: writeUrl)

            await updateBackupUrls(newUrl: writeUrl)
        } catch {
            await logManager?.error("Backup: \(error)")
        }
    }

    // Backup is in local documents directory, so no need to restore it from the shared URL
    // Pass the pluginManager reference since it's not used throughout the class like logManager
    func restoreBackup(pluginManager: PluginManager, doOverwrite: Bool) async {
        guard let backupUrl = selectedBackupUrl else {
            await logManager?.error(
                "Backup restore: Could not find backup in app directory.",
                description: "Could not find the selected backup in the local directory."
            )

            return
        }

        let backgroundContext = PersistenceController.shared.backgroundContext

        do {
            // Delete all relevant entities to prevent issues with restoration if overwrite is selected
            if doOverwrite {
                try PersistenceController.shared.batchDelete("Bookmark")
                try PersistenceController.shared.batchDelete("History")
                try PersistenceController.shared.batchDelete("HistoryEntry")
                try PersistenceController.shared.batchDelete("PluginList")
                try PersistenceController.shared.batchDelete("Source")
                try PersistenceController.shared.batchDelete("Action")
            }

            let file = try Data(contentsOf: backupUrl)

            let backup = try JSONDecoder().decode(Backup.self, from: file)

            if let bookmarks = backup.bookmarks {
                for bookmark in bookmarks {
                    PersistenceController.shared.createBookmark(bookmark, performSave: false)
                }
            }

            if let storedHistories = backup.history {
                for storedHistory in storedHistories {
                    for storedEntry in storedHistory.entries {
                        PersistenceController.shared.createHistory(
                            storedEntry,
                            performSave: false,
                            isBackup: true,
                            date: storedHistory.date
                        )
                    }
                }
            }

            let version = backup.version ?? -1

            if let storedLists = backup.sourceLists, version < 2 {
                // Only present in v1 or no version backups
                for list in storedLists {
                    try await pluginManager.addPluginList(list.urlString, existingPluginList: nil)
                }
            } else if let pluginListUrls = backup.pluginListUrls {
                // v2 and up
                for listUrl in pluginListUrls {
                    try await pluginManager.addPluginList(listUrl, existingPluginList: nil)
                }
            }

            if let sourceNames = backup.sourceNames {
                await updateRestoreCompletedMessage(newString: sourceNames.isEmpty ? "No sources need to be reinstalled" : "Reinstall sources: \(sourceNames.joined(separator: ", "))")
            }

            if let actionNames = backup.actionNames {
                await updateRestoreCompletedMessage(newString: actionNames.isEmpty ? "No actions need to be reinstalled" : "Reinstall actions: \(actionNames.joined(separator: ", "))")
            }

            PersistenceController.shared.save(backgroundContext)

            await toggleRestoreCompletedAlert()
        } catch {
            await logManager?.error(
                "Backup restore: \(error)",
                description: "A backup restore error was logged"
            )
        }
    }

    // Remove the backup from files and then the list
    // Removes an index if it's provided
    func removeBackup(backupUrl: URL, index: Int?) {
        do {
            try FileManager.default.removeItem(at: backupUrl)

            if let index {
                backupUrls.remove(at: index)
            } else {
                backupUrls.removeAll(where: { $0 == backupUrl })
            }
        } catch {
            Task {
                await logManager?.error("Backup removal: \(error)")
                print("Backup removal: \(error)")
            }
        }
    }

    func copyBackup(backupUrl: URL) {
        let backupSecured = backupUrl.startAccessingSecurityScopedResource()

        defer {
            if backupSecured {
                backupUrl.stopAccessingSecurityScopedResource()
            }
        }

        let backupsPath = FileManager.default.appDirectory.appendingPathComponent("Backups")
        let localBackupPath = backupsPath.appendingPathComponent(backupUrl.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: localBackupPath.path) {
                try FileManager.default.removeItem(at: localBackupPath)
            } else if !FileManager.default.fileExists(atPath: backupsPath.path) {
                try FileManager.default.createDirectory(atPath: backupsPath.path, withIntermediateDirectories: true, attributes: nil)
            }

            try FileManager.default.copyItem(at: backupUrl, to: localBackupPath)

            selectedBackupUrl = localBackupPath
        } catch {
            Task {
                await logManager?.error("Backup copy: \(error)")
            }
        }
    }
}
