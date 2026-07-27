import SwiftUI

@main
struct AerialWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("AerialWall", systemImage: "mountain.2.fill") {
            MenuView()
                .environmentObject(appDelegate.state)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = UpdaterService.shared
        state.start()
    }
}
