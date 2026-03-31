import SwiftUI

@main
struct MyFTPClientApp: App {
    @StateObject private var viewModel = FTPClientViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
    }
}
