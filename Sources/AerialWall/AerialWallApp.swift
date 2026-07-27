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
        showWelcomeOnFirstLaunch()
    }

    /// A menu-bar-only app gives no feedback on launch — first-time users
    /// think nothing opened. Point them at the menu bar icon once.
    private func showWelcomeOnFirstLaunch() {
        let hasShownWelcomeKey = "hasShownWelcome"
        guard !UserDefaults.standard.bool(forKey: hasShownWelcomeKey) else { return }
        UserDefaults.standard.set(true, forKey: hasShownWelcomeKey)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AerialWall lives in your menu bar"
        alert.informativeText = """
        Look for the mountain icon near the top-right of your screen and click \
        it to pick a live wallpaper.

        No wallpapers listed? Open System Settings → Wallpaper, choose an \
        aerial (Landscape, Cityscape, Underwater, or Earth), wait for it to \
        download, then hit Refresh in AerialWall.
        """
        alert.addButton(withTitle: "Got It")
        alert.runModal()
    }
}
