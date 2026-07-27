import Foundation
import Sparkle

/// Sparkle wiring. Only active when running from a real .app bundle —
/// `swift run` during development has no bundle for Sparkle to update.
final class UpdaterService {
    static let shared = UpdaterService()

    private var controller: SPUStandardUpdaterController?

    private init() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
