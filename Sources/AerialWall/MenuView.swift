import AVFoundation
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var downloader: DownloadManager

    private enum Tab: String, CaseIterable {
        case downloaded = "Downloaded"
        case all = "All"
    }

    @State private var tab: Tab = .downloaded
    @State private var searchText = ""
    @State private var categoryID: String?
    @State private var targetScreenID: String?

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 10)]

    private var screens: [(id: String, name: String)] {
        NSScreen.screens.compactMap { screen in
            WallpaperController.screenID(for: screen).map { ($0, screen.localizedName) }
        }
    }

    private var visibleAssets: [AerialAsset] {
        var shown = tab == .downloaded ? state.assets.filter(\.isDownloaded) : state.assets
        if let categoryID {
            shown = shown.filter { $0.categoryIDs.contains(categoryID) }
        }
        if !searchText.isEmpty {
            shown = shown.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return shown
    }

    private func isSelected(_ asset: AerialAsset) -> Bool {
        if let targetScreenID {
            return state.displayAssignments[targetScreenID] == asset.id
        }
        return state.selectedAssetID == asset.id
    }

    private func tileTapped(_ asset: AerialAsset) {
        if asset.isDownloaded {
            if let targetScreenID {
                // Tapping the assigned tile again clears the override.
                let isAlreadyAssigned = state.displayAssignments[targetScreenID] == asset.id
                state.assign(isAlreadyAssigned ? nil : asset.id, toDisplay: targetScreenID)
            } else {
                // "All Displays" means all: per-display overrides are replaced.
                state.selectedAssetID = asset.id
                state.displayAssignments = [:]
            }
            state.wallpaperEnabled = true
            state.offerCounterpartIfNeeded(for: asset)
        } else if downloader.progress[asset.id] != nil {
            downloader.cancel(asset)
        } else {
            state.downloadAndSelect(asset, forDisplay: targetScreenID)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Group {
                if visibleAssets.isEmpty {
                    emptyState
                } else {
                    gallery
                }
            }
            .frame(height: galleryHeight)
            Divider()
            footer
        }
        .frame(width: 320)
        .background(PanelConfigurator())
        .onAppear {
            if !state.assets.contains(where: \.isDownloaded) { tab = .all }
        }
    }

    private var header: some View {
        HStack {
            Text("AerialWall").font(.headline)
            if state.wallpaperEnabled && state.pausesOnBattery && !state.isOnACPower {
                Label("Paused on battery", systemImage: "battery.50percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $state.wallpaperEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Turn the live wallpaper on or off")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                TextField("Search wallpapers", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button {
                    state.importCustomVideos()
                } label: {
                    Image(systemName: "plus")
                }
                .controlSize(.small)
                .help("Add your own video as a wallpaper")
            }

            if screens.count > 1 {
                Picker("Display", selection: $targetScreenID) {
                    Text("All Displays").tag(String?.none)
                    ForEach(screens, id: \.id) { screen in
                        Text(screen.name).tag(String?.some(screen.id))
                    }
                }
                .controlSize(.small)
                .help("Pick which display the next selection applies to")
            }

            categoryChips
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var categoryChips: some View {
        if !state.categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(name: "All", id: nil)
                    ForEach(state.categories) { category in
                        chip(name: category.name, id: category.id)
                    }
                }
            }
        }
    }

    private func chip(name: String, id: String?) -> some View {
        Button(name) { categoryID = id }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(categoryID == id ? Color.accentColor : .secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "mountain.2").font(.largeTitle).foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "Nothing downloaded yet" : "No matches")
                .font(.callout)
            if searchText.isEmpty {
                Text("Switch to the All tab and click any wallpaper to download it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    /// Height ignores the search text so the panel doesn't resize on every
    /// keystroke — fewer results just leave empty space in the scroll area.
    private var galleryHeight: CGFloat {
        var shown = tab == .downloaded ? state.assets.filter(\.isDownloaded) : state.assets
        if let categoryID {
            shown = shown.filter { $0.categoryIDs.contains(categoryID) }
        }
        let rows = max(1, (shown.count + 1) / 2)
        return min(CGFloat(rows) * 104 + 14, 380)
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(visibleAssets) { asset in
                    AssetTile(
                        asset: asset,
                        thumbnail: state.thumbnails[asset.id],
                        isSelected: isSelected(asset),
                        downloadProgress: downloader.progress[asset.id],
                        onDelete: asset.isDeletable ? { state.deleteDownload(asset) } : nil
                    ) {
                        tileTapped(asset)
                    }
                    .contextMenu {
                        if asset.isDeletable {
                            Button("Remove Download") { state.deleteDownload(asset) }
                        }
                    }
                }
            }
            .padding(12)
        }
        .opacity(state.wallpaperEnabled ? 1 : 0.5)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Only play on power cable", isOn: $state.pausesOnBattery)
            Toggle("Match light/dark mode", isOn: $state.matchesAppearance)
            Toggle("Launch at login", isOn: Binding(
                get: { state.launchesAtLogin },
                set: { state.launchesAtLogin = $0 }
            ))
            HStack {
                Picker("Shuffle", selection: $state.shuffleIntervalSeconds) {
                    Text("Off").tag(0.0)
                    Text("Every 15 min").tag(900.0)
                    Text("Every hour").tag(3600.0)
                    Text("Every day").tag(86400.0)
                }
                .controlSize(.small)
                Button {
                    state.nextWallpaper()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .controlSize(.small)
                .help("Next wallpaper (⌃⌥⌘N)")
            }
            if state.managedVideoCount > 0 {
                Text("\(state.managedVideoCount) video\(state.managedVideoCount == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: state.managedVideoBytes, countStyle: .file)) on disk")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Button("Refresh") { state.refreshLibrary() }
                Button("Check for Updates…") { UpdaterService.shared.checkForUpdates() }
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(12)
    }
}

private struct AssetTile: View {
    let asset: AerialAsset
    let thumbnail: NSImage?
    let isSelected: Bool
    let downloadProgress: Double?
    let onDelete: (() -> Void)?
    let action: () -> Void

    @State private var isHovering = false
    @State private var showsLivePreview = false
    @ObservedObject private var previewCache = PreviewImageCache.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                preview
                    .frame(width: 132, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    )
                    .overlay(alignment: .bottomTrailing) { badge }
                    .overlay(alignment: .topTrailing) { deleteButton }
                Text(asset.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
        .help(asset.isDownloaded ? asset.name : "Click to download \(asset.name)")
        .onHover { hovering in
            isHovering = hovering
            if !hovering { showsLivePreview = false }
        }
        .task(id: isHovering) {
            guard isHovering, asset.isDownloaded else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if isHovering { showsLivePreview = true }
        }
    }

    @ViewBuilder private var deleteButton: some View {
        if isHovering, let onDelete {
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Remove download")
        }
    }

    @ViewBuilder private var preview: some View {
        if showsLivePreview, let localURL = asset.localURL {
            LoopingPlayerView(url: localURL)
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
        } else if let previewURL = asset.previewURL {
            if let image = previewCache.image(for: previewURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
            } else {
                placeholder
                    .onAppear { previewCache.load(previewURL) }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
            .aspectRatio(16 / 9, contentMode: .fill)
            .overlay(Image(systemName: "mountain.2").foregroundStyle(.secondary))
    }

    @ViewBuilder private var badge: some View {
        if let downloadProgress {
            ProgressView(value: downloadProgress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .padding(3)
                .background(.ultraThinMaterial, in: Circle())
                .padding(4)
                .help("Downloading — click to cancel")
        } else if !asset.isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white, .black.opacity(0.45))
                .padding(4)
        }
    }
}

/// Tunes the MenuBarExtra window: dismiss when focus moves elsewhere
/// (other menu bar items, other apps) and sit snug under the menu bar
/// instead of floating a few points below it.
private struct PanelConfigurator: NSViewRepresentable {
    final class ConfigView: NSView {
        private var keyObserver: Any?
        private var resignObserver: Any?
        private var resizeObserver: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Self.configure(window)
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Self.configure(window)
            }
            // Never hidesOnDeactivate here: the status-item click opens the
            // panel while the app is inactive, so AppKit would hide it
            // immediately. Closing on resign-key dismisses it when focus
            // moves to another menu bar item, window, or app.
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow, window.isVisible else { return }
                window.close()
            }
            // Content-driven resizes (tab or category switches) leave a stale
            // rounded mask and shadow behind unless recomputed.
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Self.configure(window)
            }
        }

        /// Rounding must target the window's frame view (which draws the
        /// backdrop) and be reapplied on every open and resize — AppKit
        /// rebuilds these layers between appearances.
        private static func configure(_ window: NSWindow) {
            window.isOpaque = false
            window.backgroundColor = .clear
            if let frameView = window.contentView?.superview {
                frameView.wantsLayer = true
                frameView.layer?.cornerRadius = 16
                frameView.layer?.cornerCurve = .continuous
                frameView.layer?.masksToBounds = true
            }
            snugToMenuBar(window)
            window.invalidateShadow()
        }

        private static func snugToMenuBar(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            var frame = window.frame
            frame.origin.y = screen.visibleFrame.maxY - frame.height
            window.setFrame(frame, display: false)
        }

        deinit {
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
            }
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }
    }

    func makeNSView(context: Context) -> ConfigView { ConfigView() }
    func updateNSView(_ nsView: ConfigView, context: Context) {}
}

/// Muted, looping inline video used for the hover preview.
private struct LoopingPlayerView: NSViewRepresentable {
    let url: URL

    final class PlayerView: NSView {
        private let player: AVQueuePlayer
        private let looper: AVPlayerLooper

        init(url: URL) {
            player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            super.init(frame: .zero)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            wantsLayer = true
            layer = playerLayer
            player.play()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }

    func makeNSView(context: Context) -> PlayerView { PlayerView(url: url) }
    func updateNSView(_ nsView: PlayerView, context: Context) {}
}
