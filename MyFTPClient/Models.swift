import Foundation

struct ConnectionConfig: Sendable {
    let server: String
    let type: String
    let port: Int
    let username: String
    let password: String
    let privateKeyPath: String

    static func loadFromBundle() -> ConnectionConfig {
        let info = Bundle.main.infoDictionary ?? [:]

        return ConnectionConfig(
            server: info["FTPServer"] as? String ?? "ssh.strato.de",
            type: info["FTPType"] as? String ?? "sftp",
            port: info["FTPPort"] as? Int ?? 22,
            username: info["FTPUsername"] as? String ?? "peter-petermann.de",
            password: info["FTPPassword"] as? String ?? "xxxxx",
            privateKeyPath: info["FTPPrivateKeyPath"] as? String ?? ""
        )
    }

    var maskedPassword: String {
        String(repeating: "*", count: max(password.count, 5))
    }

    var authenticationDescription: String {
        let keyPath = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyPath.isEmpty ? "Passwort" : "SSH-Key"
    }
}

enum LocalRoot: String, CaseIterable, Identifiable, Sendable {
    case desktop = "Desktop"

    var id: String { rawValue }

    var directoryURL: URL {
        let fileManager = FileManager.default

        switch self {
        case .desktop:
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
    }
}

enum FileLocation: Sendable {
    case local
    case remote
}

struct FileItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let location: FileLocation
    let sizeDescription: String
}

struct RemoteDirectoryListing: Sendable {
    let currentPath: String
    let items: [FileItem]
}
