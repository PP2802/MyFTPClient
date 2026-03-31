import Foundation

enum SFTPServiceError: LocalizedError {
    case authenticationFailed(String?)
    case invalidPrivateKey
    case invalidRemotePath
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let details):
            if let details, !details.isEmpty {
                return "Authentifizierung fehlgeschlagen: \(details)"
            }
            return "Authentifizierung fehlgeschlagen."
        case .invalidPrivateKey:
            return "Die konfigurierte SSH-Key-Datei konnte nicht verwendet werden."
        case .invalidRemotePath:
            return "Der Remote-Pfad konnte nicht aufgelöst werden."
        case .commandFailed(let message):
            return message
        }
    }
}

final class SFTPService: @unchecked Sendable {
    func testConnection(config: ConnectionConfig) async throws {
        _ = try await runSFTPSession(config: config, commands: ["pwd"])
    }

    func listDirectory(config: ConnectionConfig, path: String) async throws -> RemoteDirectoryListing {
        let targetPath = normalizedRemotePath(path)
        let output = try await runSFTPSession(
            config: config,
            commands: [
                "cd \(sftpQuote(targetPath))",
                "pwd",
                "ls -la"
            ]
        )

        if output.contains("Couldn't canonicalize") || output.contains("No such file or directory") {
            throw SFTPServiceError.invalidRemotePath
        }

        let currentPath = try parseRemoteWorkingDirectory(from: output)
        let items = parseDirectoryListing(from: output, currentPath: currentPath)
        return RemoteDirectoryListing(currentPath: currentPath, items: items)
    }

    func upload(localURLs: [URL], to remotePath: String, config: ConnectionConfig) async throws {
        let targetPath = normalizedRemotePath(remotePath)
        var commands = ["cd \(sftpQuote(targetPath))"]

        for localURL in localURLs {
            commands.append("put \(sftpQuote(localURL.path))")
        }

        let output = try await runSFTPSession(config: config, commands: commands)
        try validateTransferOutput(output)
    }

    func download(remotePaths: [String], to localDirectory: URL, config: ConnectionConfig) async throws {
        let commands = remotePaths.map { remotePath in
            let filename = URL(fileURLWithPath: remotePath).lastPathComponent
            let destination = localDirectory.appendingPathComponent(filename).path
            return "get \(sftpQuote(remotePath)) \(sftpQuote(destination))"
        }

        let output = try await runSFTPSession(config: config, commands: commands)
        try validateTransferOutput(output)
    }

    private func runSFTPSession(config: ConnectionConfig, commands: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try self.runSFTPSessionSync(config: config, commands: commands)
        }.value
    }

    private func runSFTPSessionSync(config: ConnectionConfig, commands: [String]) throws -> String {
        let scriptURL = try writeExpectScript()
        defer {
            try? FileManager.default.removeItem(at: scriptURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        process.arguments = [scriptURL.path, config.password, "--sftp--"] + makeSFTPArguments(config: config) + ["--commands--"] + commands

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        if output.contains("__AUTH_FAILED__") {
            throw SFTPServiceError.authenticationFailed(extractFailureReason(from: output))
        }

        if output.contains("__TIMEOUT__") {
            throw SFTPServiceError.commandFailed("Zeitüberschreitung bei der SFTP-Verbindung.")
        }

        if process.terminationStatus != 0 {
            throw SFTPServiceError.commandFailed(cleanOutput(output))
        }

        return output
    }

    private func makeSFTPArguments(config: ConnectionConfig) -> [String] {
        var args = [
            "-4",
            "-o", "PreferredAuthentications=keyboard-interactive,password",
            "-o", "PubkeyAuthentication=no",
            "-o", "KbdInteractiveAuthentication=yes",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", "\(config.port)"
        ]

        let keyPath = config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyPath.isEmpty {
            guard FileManager.default.fileExists(atPath: keyPath) else {
                return ["__INVALID_PRIVATE_KEY__"]
            }
            args += ["-i", keyPath]
        }

        args.append("\(config.username)@\(config.server)")
        return args
    }

    private func writeExpectScript() throws -> URL {
        let script = """
        set timeout 20
        log_user 1
        if {[llength $argv] < 4} {
            puts stderr "__INVALID_ARGS__"
            exit 2
        }
        set password [lindex $argv 0]
        set sftpMarker [lsearch -exact $argv "--sftp--"]
        set commandMarker [lsearch -exact $argv "--commands--"]
        if {$sftpMarker < 0 || $commandMarker < 0 || $commandMarker <= $sftpMarker} {
            puts stderr "__INVALID_ARGS__"
            exit 2
        }
        set sftpArgs [lrange $argv [expr {$sftpMarker + 1}] [expr {$commandMarker - 1}]]
        set commands [lrange $argv [expr {$commandMarker + 1}] end]
        if {[lindex $sftpArgs 0] == "__INVALID_PRIVATE_KEY__"} {
            puts stderr "__INVALID_PRIVATE_KEY__"
            exit 3
        }
        set commandIndex 0
        set sentBye 0
        eval spawn [list /usr/bin/sftp] $sftpArgs
        expect {
            -re {[Pp]assword:|Enter PASSCODE:} {
                send -- "$password\\r"
                exp_continue
            }
            -re {Permission denied|Authentication failed} {
                puts "__AUTH_FAILED__"
                exp_continue
            }
            -re {sftp>} {
                if {$commandIndex < [llength $commands]} {
                    set command [lindex $commands $commandIndex]
                    incr commandIndex
                    send -- "$command\\r"
                } elseif {!$sentBye} {
                    set sentBye 1
                    send -- "bye\\r"
                }
                exp_continue
            }
            timeout {
                puts "__TIMEOUT__"
                exit 124
            }
            eof
        }
        """

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("expect")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func normalizedRemotePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "." : trimmed
    }

    private func parseRemoteWorkingDirectory(from output: String) throws -> String {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Remote working directory:") {
                let path = trimmed.replacingOccurrences(of: "Remote working directory:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return path
                }
            }
        }

        throw SFTPServiceError.invalidRemotePath
    }

    private func parseDirectoryListing(from output: String, currentPath: String) -> [FileItem] {
        let lines = output.components(separatedBy: .newlines)
        var listingStarted = false
        var items: [FileItem] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("sftp> ls -la") {
                listingStarted = true
                continue
            }

            if !listingStarted || trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("sftp>") || trimmed.hasPrefix("Connection closed") {
                break
            }

            guard let item = parseListingLine(trimmed, currentPath: currentPath) else {
                continue
            }

            if item.name == "." || item.name == ".." {
                continue
            }

            items.append(item)
        }

        return items.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func parseListingLine(_ line: String, currentPath: String) -> FileItem? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9 else {
            return nil
        }

        let permissions = String(parts[0])
        let isDirectory = permissions.hasPrefix("d")
        let sizeDescription = isDirectory ? "Ordner" : "\(parts[4]) B"
        let name = parts[8...].joined(separator: " ")
        let fullPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"

        return FileItem(
            id: "remote::\(fullPath)",
            name: name,
            path: fullPath,
            isDirectory: isDirectory,
            location: .remote,
            sizeDescription: sizeDescription
        )
    }

    private func validateTransferOutput(_ output: String) throws {
        let failures = [
            "Couldn't",
            "No such file or directory",
            "Failure",
            "not found",
            "Permission denied"
        ]

        if failures.contains(where: { output.localizedCaseInsensitiveContains($0) }) {
            throw SFTPServiceError.commandFailed(cleanOutput(output))
        }
    }

    private func extractFailureReason(from output: String) -> String? {
        let cleaned = cleanOutput(output)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func cleanOutput(_ output: String) -> String {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty &&
                !$0.hasPrefix("spawn /usr/bin/sftp") &&
                !$0.hasPrefix("Warning: Permanently added") &&
                !$0.hasPrefix("sftp>") &&
                $0 != "__AUTH_FAILED__" &&
                $0 != "__TIMEOUT__"
            }

        return lines.joined(separator: "\n")
    }

    private func sftpQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
