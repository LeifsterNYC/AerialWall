import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var assets: [AerialAsset] = []
    @Published var categories: [AerialCategory] = []
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var isOnACPower = PowerMonitor.isOnACPower()
    @Published var managedVideoCount = 0
    @Published var managedVideoBytes: Int64 = 0

    /// Per-display overrides: screen UUID → asset ID. Screens without an
    /// entry play the main selection.
    @Published var displayAssignments: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "displayAssignments") as? [String: String]) ?? [:]
    {
        didSet {
            UserDefaults.standard.set(displayAssignments, forKey: "displayAssignments")
            applySelection()
        }
    }

    @AppStorage("selectedAssetID") var selectedAssetID = "" {
        didSet { applySelection() }
    }
    @AppStorage("wallpaperEnabled") var wallpaperEnabled = true {
        didSet { applySelection() }
    }
    @AppStorage("pausesOnBattery") var pausesOnBattery = true {
        didSet { applyPlayback() }
    }
    @AppStorage("shuffleIntervalSeconds") var shuffleIntervalSeconds = 0.0 {
        didSet { scheduleShuffle() }
    }
    @AppStorage("matchesAppearance") var matchesAppearance = false {
        didSet { applyAppearanceMatch() }
    }

    let downloader = DownloadManager()

    private let wallpaper = WallpaperController()
    private let powerMonitor = PowerMonitor()
    private var activeSignature = ""
    private var thumbnailTask: Task<Void, Never>?
    private var pendingSelectionID: String?
    private var pendingSelectionDisplayID: String?
    private var shuffleTimer: Timer?
    private var nextWallpaperHotKey: GlobalHotKey?

    var isSystemDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

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
        downloader.onComplete = { [weak self] assetID in
            guard let self else { return }
            refreshLibrary()
            if pendingSelectionID == assetID {
                pendingSelectionID = nil
                if let screenID = pendingSelectionDisplayID {
                    pendingSelectionDisplayID = nil
                    assign(assetID, toDisplay: screenID)
                } else {
                    selectedAssetID = assetID
                }
                wallpaperEnabled = true
                if let asset = assets.first(where: { $0.id == assetID }) {
                    offerCounterpartIfNeeded(for: asset)
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyAppearanceMatch() }
        }
        nextWallpaperHotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in self?.nextWallpaper() }
        }
        scheduleShuffle()
        refreshLibrary()
    }

    func refreshLibrary() {
        assets = AerialLibrary.scan()
        categories = AerialLibrary.categories()
        refreshStorageStats()
        generateMissingThumbnails()
        // The appearance may have flipped while the app wasn't running.
        applyAppearanceMatch()
        applySelection()
    }

    // MARK: - Downloads and imports

    /// Starts downloading an aerial and selects it once it lands — for one
    /// display when one is targeted, otherwise as the everywhere fallback.
    func downloadAndSelect(_ asset: AerialAsset, forDisplay screenID: String? = nil) {
        pendingSelectionID = asset.id
        pendingSelectionDisplayID = screenID
        downloader.download(asset)
    }

    func deleteDownload(_ asset: AerialAsset) {
        guard asset.isDeletable, let localURL = asset.localURL else { return }
        do {
            try FileManager.default.removeItem(at: localURL)
        } catch {
            NSLog("Failed to delete \(asset.name): \(error)")
            return
        }
        thumbnails[asset.id] = nil
        refreshLibrary()
    }

    func importCustomVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.message = "Choose videos to use as wallpapers"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let sources = panel.urls.filter { AerialLibrary.videoExtensions.contains($0.pathExtension.lowercased()) }
        let importedIDs = sources.map { $0.deletingPathExtension().lastPathComponent.uppercased() }
        Task.detached {
            let fm = FileManager.default
            try? fm.createDirectory(at: AerialLibrary.customDirectory, withIntermediateDirectories: true)
            for source in sources {
                let destination = AerialLibrary.customDirectory.appendingPathComponent(source.lastPathComponent)
                try? fm.removeItem(at: destination)
                do {
                    try fm.copyItem(at: source, to: destination)
                } catch {
                    NSLog("Failed to import \(source.lastPathComponent): \(error)")
                }
            }
            await MainActor.run {
                // A re-import keeps its id and path; drop cached state so the
                // new content actually shows.
                for id in importedIDs {
                    self.thumbnails[id] = nil
                }
                self.activeSignature = ""
                self.refreshLibrary()
            }
        }
    }

    private func refreshStorageStats() {
        var count = 0
        var bytes: Int64 = 0
        for asset in assets {
            guard let localURL = asset.localURL else { continue }
            count += 1
            bytes += Int64((try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        managedVideoCount = count
        managedVideoBytes = bytes
    }

    // MARK: - Shuffle and appearance

    /// Jump to a random other downloaded wallpaper (menu button and ⌃⌥⌘N).
    func nextWallpaper() {
        wallpaperEnabled = true
        shuffleNow()
    }

    private func scheduleShuffle() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
        guard shuffleIntervalSeconds > 0 else { return }
        shuffleTimer = Timer.scheduledTimer(withTimeInterval: shuffleIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.wallpaperEnabled else { return }
                self.shuffleNow()
            }
        }
    }

    private func shuffleNow() {
        let pool = assets.filter {
            $0.isDownloaded && $0.id != selectedAssetID && isPeriodAppropriate($0)
        }
        guard let pick = pool.randomElement() else { return }
        selectedAssetID = pick.id
    }

    /// When a picked wallpaper has a day/night twin that isn't downloaded,
    /// offer to grab it so appearance matching has both halves.
    func offerCounterpartIfNeeded(for asset: AerialAsset) {
        guard let variant = asset.dayNightVariant,
              let counterpart = assets.first(where: {
                  $0.dayNightVariant?.stem == variant.stem
                      && $0.dayNightVariant?.isNight == !variant.isNight
              }),
              !counterpart.isDownloaded,
              counterpart.remoteURL != nil,
              downloader.progress[counterpart.id] == nil
        else { return }
        let declinedKey = "declinedCounterpartOffers"
        var declined = UserDefaults.standard.stringArray(forKey: declinedKey) ?? []
        guard !declined.contains(counterpart.id) else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Download \(counterpart.name) too?"
        alert.informativeText = "\(asset.name) has a \(variant.isNight ? "day" : "night") version. With both downloaded, AerialWall can swap them automatically when your Mac switches between light and dark mode."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "No Thanks")
        if alert.runModal() == .alertFirstButtonReturn {
            downloader.download(counterpart)
        } else {
            declined.append(counterpart.id)
            UserDefaults.standard.set(declined, forKey: declinedKey)
        }
    }

    /// With appearance matching on, keep day variants out of dark mode and
    /// night variants out of light mode.
    private func isPeriodAppropriate(_ asset: AerialAsset) -> Bool {
        guard matchesAppearance, let variant = asset.dayNightVariant else { return true }
        return variant.isNight == isSystemDark
    }

    private func applyAppearanceMatch() {
        guard matchesAppearance else { return }
        if let swap = counterpartForCurrentAppearance(of: selectedAssetID) {
            selectedAssetID = swap.id
        }
        for (screenID, assetID) in displayAssignments {
            if let swap = counterpartForCurrentAppearance(of: assetID) {
                displayAssignments[screenID] = swap.id
            }
        }
    }

    /// The downloaded day/night twin matching the current appearance, if the
    /// given asset is currently the wrong variant.
    private func counterpartForCurrentAppearance(of assetID: String) -> AerialAsset? {
        guard let asset = assets.first(where: { $0.id == assetID }),
              let variant = asset.dayNightVariant,
              variant.isNight != isSystemDark
        else { return nil }
        return assets.first {
            $0.isDownloaded
                && $0.dayNightVariant?.stem == variant.stem
                && $0.dayNightVariant?.isNight == isSystemDark
        }
    }

    // MARK: - Playback

    func assign(_ assetID: String?, toDisplay screenID: String) {
        if let assetID {
            displayAssignments[screenID] = assetID
        } else {
            displayAssignments.removeValue(forKey: screenID)
        }
    }

    private func applySelection() {
        guard wallpaperEnabled else {
            activeSignature = ""
            wallpaper.clear()
            return
        }
        let fallback = assets.first { $0.id == selectedAssetID }?.localURL
        var perScreen: [String: URL] = [:]
        for (screenID, assetID) in displayAssignments {
            if let url = assets.first(where: { $0.id == assetID })?.localURL {
                perScreen[screenID] = url
            }
        }
        guard fallback != nil || !perScreen.isEmpty else {
            activeSignature = ""
            wallpaper.clear()
            return
        }
        let signature = (fallback?.path ?? "")
            + "|" + perScreen.map { "\($0.key)=\($0.value.path)" }.sorted().joined(separator: ",")
        if signature != activeSignature {
            activeSignature = signature
            wallpaper.setVideos(fallback: fallback, perScreen: perScreen)
        }
        applyPlayback()
    }

    private func applyPlayback() {
        guard wallpaperEnabled, !activeSignature.isEmpty else { return }
        let isBatteryBlocked = pausesOnBattery && !isOnACPower
        if isBatteryBlocked || !wallpaper.isDesktopVisible {
            wallpaper.pause()
        } else {
            wallpaper.play()
        }
    }

    // MARK: - Thumbnails

    /// Decodes a few thumbnails at a time, in display order — a large library
    /// would otherwise spin up one 4K video decoder per asset simultaneously.
    private func generateMissingThumbnails() {
        thumbnailTask?.cancel()
        let pending = assets.filter { $0.isDownloaded && thumbnails[$0.id] == nil }
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
}
