import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: FTPClientViewModel

    var body: some View {
        Group {
            if viewModel.isConnected {
                FileExplorerView()
            } else {
                ConnectionView()
            }
        }
        .alert("Fehler", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var viewModel: FTPClientViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("SFTP-Verbindung")
                .font(.largeTitle)
                .bold()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Server")
                        .foregroundStyle(.secondary)
                    Text(viewModel.config.server)
                }
                GridRow {
                    Text("Typ")
                        .foregroundStyle(.secondary)
                    Text(viewModel.config.type.uppercased())
                }
                GridRow {
                    Text("Port")
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.config.port)")
                }
                GridRow {
                    Text("Benutzer")
                        .foregroundStyle(.secondary)
                    Text(viewModel.config.username)
                }
                GridRow {
                    Text("Passwort")
                        .foregroundStyle(.secondary)
                    Text(viewModel.config.maskedPassword)
                }
                GridRow {
                    Text("Authentifizierung")
                        .foregroundStyle(.secondary)
                    Text(viewModel.config.authenticationDescription)
                }
                if !viewModel.config.privateKeyPath.isEmpty {
                    GridRow {
                        Text("Key-Datei")
                            .foregroundStyle(.secondary)
                        Text(viewModel.config.privateKeyPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(24)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button("Diagnose") {
                    Task {
                        await viewModel.runDiagnostics()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isBusy)

                Button("Verbinden") {
                    Task {
                        await viewModel.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isBusy)
            }

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.large)
            }

            Text(viewModel.statusMessage)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct FileExplorerView: View {
    @EnvironmentObject private var viewModel: FTPClientViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verbunden mit \(viewModel.config.server)")
                        .font(.title2)
                        .bold()
                    Text(viewModel.statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(viewModel.transferButtonTitle) {
                    Task {
                        await viewModel.transferSelection()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }

            HSplitView {
                LocalPaneView()
                RemotePaneView()
            }

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
    }
}

struct LocalPaneView: View {
    @EnvironmentObject private var viewModel: FTPClientViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lokal")
                    .font(.headline)

                Text(viewModel.currentLocalDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Hoch") {
                    viewModel.navigateLocalUp()
                }
                .disabled(viewModel.currentLocalDirectory.path == viewModel.currentLocalRoot.directoryURL.path)

                Button("Aktualisieren") {
                    viewModel.refreshLocalFiles()
                }
            }

            List(viewModel.localItems) { item in
                FileRow(
                    item: item,
                    isSelected: viewModel.selectedLocalItems.contains(item.id)
                )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleLocalSelection(for: item)
                    }
                    .onTapGesture(count: 2) {
                        viewModel.openLocalDirectory(item)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct RemotePaneView: View {
    @EnvironmentObject private var viewModel: FTPClientViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Server")
                    .font(.headline)

                Text(viewModel.currentRemotePath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Hoch") {
                    Task {
                        await viewModel.navigateRemoteUp()
                    }
                }
                .disabled(viewModel.currentRemotePath == "/")

                Button("Aktualisieren") {
                    Task {
                        await viewModel.refreshRemoteFiles()
                    }
                }
            }

            List(viewModel.remoteItems) { item in
                FileRow(
                    item: item,
                    isSelected: viewModel.selectedRemoteItems.contains(item.id)
                )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleRemoteSelection(for: item)
                    }
                    .onTapGesture(count: 2) {
                        Task {
                            await viewModel.openRemoteDirectory(item)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FileRow: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        HStack {
            Group {
                if item.isDirectory {
                    Color.clear
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
            .frame(width: 16)
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.isDirectory ? .yellow : .blue)
            Text(item.name)
            Spacer()
            Text(item.sizeDescription)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
    }
}
