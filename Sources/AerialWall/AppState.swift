import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var assets: [AerialAsset] = []
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var isOnACPower = PowerMonitor.isOnACPower()

    @AppStorage("selectedAssetID") var selectedAssetID = "" {
        didSet { applySelection() }
    }
    @AppStorage("pausesOnBattery") var pausesOnBattery = true {
        didSet { applyPlayback() }
    }

    private let wallpaper = WallpaperController()
    private let powerMonitor = PowerMonitor()

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch-at-login change failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    func start() {
        powerMonitor.onChange = { [weak self] isOnAC in
            Task { @MainActor in
                self?.isOnACPower = isOnAC
                self?.applyPlayback()
            }
        }
        powerMonitor.start()
        refreshLibrary()
        applySelection()
    }

    func refreshLibrary() {
        assets = AerialLibrary.scan()
        for asset in assets where thumbnails[asset.id] == nil {
            Task {
                if let image = await AerialLibrary.thumbnail(for: asset) {
                    self.thumbnails[asset.id] = image
                }
            }
        }
    }

    private func applySelection() {
        guard let asset = assets.first(where: { $0.id == selectedAssetID }) else {
            wallpaper.clear()
            return
        }
        wallpaper.setVideo(url: asset.url)
        applyPlayback()
    }

    private func applyPlayback() {
        guard !selectedAssetID.isEmpty else { return }
        if pausesOnBattery && !isOnACPower {
            wallpaper.pause()
        } else {
            wallpaper.play()
        }
    }
}
