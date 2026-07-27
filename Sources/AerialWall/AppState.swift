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
    @AppStorage("wallpaperEnabled") var wallpaperEnabled = true {
        didSet { applySelection() }
    }
    @AppStorage("pausesOnBattery") var pausesOnBattery = true {
        didSet { applyPlayback() }
    }

    private let wallpaper = WallpaperController()
    private let powerMonitor = PowerMonitor()
    private var activeAssetID: String?

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
        wallpaper.onDesktopVisibilityChange = { [weak self] _ in
            self?.applyPlayback()
        }
        refreshLibrary()
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
        applySelection()
    }

    private func applySelection() {
        guard wallpaperEnabled, let asset = assets.first(where: { $0.id == selectedAssetID }) else {
            activeAssetID = nil
            wallpaper.clear()
            return
        }
        if asset.id != activeAssetID {
            activeAssetID = asset.id
            wallpaper.setVideo(url: asset.url)
        }
        applyPlayback()
    }

    private func applyPlayback() {
        guard wallpaperEnabled, !selectedAssetID.isEmpty else { return }
        let isBatteryBlocked = pausesOnBattery && !isOnACPower
        if isBatteryBlocked || !wallpaper.isDesktopVisible {
            wallpaper.pause()
        } else {
            wallpaper.play()
        }
    }
}
