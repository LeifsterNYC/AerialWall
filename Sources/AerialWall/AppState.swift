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
    private var thumbnailTask: Task<Void, Never>?

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
        generateMissingThumbnails()
        applySelection()
    }

    /// Decodes a few thumbnails at a time, in display order — a large library
    /// would otherwise spin up one 4K video decoder per asset simultaneously.
    private func generateMissingThumbnails() {
        thumbnailTask?.cancel()
        let pending = assets.filter { thumbnails[$0.id] == nil }
        guard !pending.isEmpty else { return }
        thumbnailTask = Task {
            for start in stride(from: 0, to: pending.count, by: 4) {
                guard !Task.isCancelled else { return }
                let batch = pending[start..<min(start + 4, pending.count)]
                await withTaskGroup(of: (String, NSImage?).self) { group in
                    for asset in batch {
                        group.addTask { (asset.id, await AerialLibrary.thumbnail(for: asset)) }
                    }
                    for await (id, image) in group {
                        if let image { self.thumbnails[id] = image }
                    }
                }
            }
        }
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
