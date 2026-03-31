import Foundation
import SwiftUI

@MainActor
final class FTPClientViewModel: ObservableObject {
    @Published var config = ConnectionConfig.loadFromBundle()
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var statusMessage = "Noch nicht verbunden."

    @Published var currentLocalRoot: LocalRoot = .desktop
    @Published var currentLocalDirectory: URL = LocalRoot.desktop.directoryURL
    @Published var localItems: [FileItem] = []
    @Published var selectedLocalItems = Set<String>()

    @Published var currentRemotePath = "."
    @Published var remoteItems: [FileItem] = []
    @Published var selectedRemoteItems = Set<String>()

    private let service = SFTPService()

    init() {
        currentLocalDirectory = LocalRoot.desktop.directoryURL
        refreshLocalFiles()
    }

    func connect() async {
        isBusy = true
        errorMessage = nil
        statusMessage = "Verbinde mit \(config.server) ..."

        do {
            try await service.testConnection(config: config)

            isConnected = true
            statusMessage = "Verbindung hergestellt."
            refreshLocalFiles()
            await refreshRemoteFiles()
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
            statusMessage = "Verbindung fehlgeschlagen."
        }

        isBusy = false
    }

    func runDiagnostics() async {
        isBusy = true
        errorMessage = nil
        statusMessage = "Prüfe Anmeldung ..."

        do {
            try await service.testConnection(config: config)
            statusMessage = "Diagnose erfolgreich: Anmeldung akzeptiert."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Diagnose fehlgeschlagen."
        }

        isBusy = false
    }

    func changeLocalRoot(to root: LocalRoot) {
        currentLocalRoot = root
        currentLocalDirectory = root.directoryURL
        refreshLocalFiles()
    }

    func refreshRemoteFiles() async {
        guard isConnected else { return }

        isBusy = true
        errorMessage = nil

        do {
            let listing = try await service.listDirectory(config: config, path: currentRemotePath)

            currentRemotePath = listing.currentPath
            remoteItems = listing.items
        } catch {
            errorMessage = error.localizedDescription
        }

        isBusy = false
    }

    var selectedLocalDirectory: FileItem? {
        let matches = localItems.filter { selectedLocalItems.contains($0.id) && $0.isDirectory }
        return matches.count == 1 ? matches[0] : nil
    }

    var selectedRemoteDirectory: FileItem? {
        let matches = remoteItems.filter { selectedRemoteItems.contains($0.id) && $0.isDirectory }
        return matches.count == 1 ? matches[0] : nil
    }

    var localTransferCandidates: [FileItem] {
        localItems.filter { selectedLocalItems.contains($0.id) && !$0.isDirectory }
    }

    var remoteTransferCandidates: [FileItem] {
        remoteItems.filter { selectedRemoteItems.contains($0.id) && !$0.isDirectory }
    }

    var transferButtonTitle: String {
        let hasLocal = !localTransferCandidates.isEmpty
        let hasRemote = !remoteTransferCandidates.isEmpty

        if hasLocal && !hasRemote {
            return "Hochladen"
        }

        if hasRemote && !hasLocal {
            return "Herunterladen"
        }

        return "Übertragen"
    }

    func toggleLocalSelection(for item: FileItem) {
        guard !item.isDirectory else { return }
        if selectedLocalItems.contains(item.id) {
            selectedLocalItems.remove(item.id)
        } else {
            selectedLocalItems.insert(item.id)
        }
    }

    func toggleRemoteSelection(for item: FileItem) {
        guard !item.isDirectory else { return }
        if selectedRemoteItems.contains(item.id) {
            selectedRemoteItems.remove(item.id)
        } else {
            selectedRemoteItems.insert(item.id)
        }
    }

    func openLocalDirectory(_ item: FileItem) {
        guard item.isDirectory else { return }

        let url = URL(fileURLWithPath: item.path)
        currentLocalDirectory = url
        refreshLocalFiles()
    }

    func navigateLocalUp() {
        let rootURL = currentLocalRoot.directoryURL
        guard currentLocalDirectory.path != rootURL.path else { return }

        let parent = currentLocalDirectory.deletingLastPathComponent()
        guard parent.path.hasPrefix(rootURL.path) else {
            currentLocalDirectory = rootURL
            refreshLocalFiles()
            return
        }

        currentLocalDirectory = parent
        refreshLocalFiles()
    }

    func openRemoteDirectory(_ item: FileItem) async {
        guard item.isDirectory else { return }
        currentRemotePath = item.path
        await refreshRemoteFiles()
    }

    func navigateRemoteUp() async {
        guard currentRemotePath != "/" else { return }

        let parent = URL(fileURLWithPath: currentRemotePath).deletingLastPathComponent().path
        currentRemotePath = parent.isEmpty ? "/" : parent
        await refreshRemoteFiles()
    }

    func transferSelection() async {
        let localSelection = localTransferCandidates
        let remoteSelection = remoteTransferCandidates

        guard !localSelection.isEmpty || !remoteSelection.isEmpty else {
            errorMessage = "Es ist keine übertragbare Datei ausgewählt."
            return
        }

        guard localSelection.isEmpty || remoteSelection.isEmpty else {
            errorMessage = "Bitte Dateien nur auf einer Seite auswählen."
            return
        }

        isBusy = true
        errorMessage = nil
        statusMessage = "Übertragung läuft ..."

        do {
            if !localSelection.isEmpty {
                let localURLs = localSelection.map { URL(fileURLWithPath: $0.path) }
                try await service.upload(localURLs: localURLs, to: currentRemotePath, config: config)
            }

            if !remoteSelection.isEmpty {
                let remotePaths = remoteSelection.map(\.path)
                try await service.download(remotePaths: remotePaths, to: currentLocalDirectory, config: config)
            }

            statusMessage = "Übertragung abgeschlossen."
            selectedLocalItems.removeAll()
            selectedRemoteItems.removeAll()
            refreshLocalFiles()
            await refreshRemoteFiles()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Übertragung fehlgeschlagen."
        }

        isBusy = false
    }

    private func items(at url: URL) throws -> [FileItem] {
        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return try items.compactMap { fileURL in
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values.isDirectory ?? false
            let sizeDescription = isDirectory ? "Ordner" : "\((values.fileSize ?? 0)) B"

            return FileItem(
                id: "local::\(fileURL.path)",
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                isDirectory: isDirectory,
                location: .local,
                sizeDescription: sizeDescription
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func refreshLocalFiles() {
        do {
            localItems = try items(at: currentLocalDirectory)
            selectedLocalItems.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
