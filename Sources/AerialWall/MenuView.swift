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

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 10)]

    private var visibleAssets: [AerialAsset] {
        var shown = tab == .downloaded ? state.assets.filter(\.isDownloaded) : state.assets
        if !searchText.isEmpty {
            shown = shown.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return shown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            if visibleAssets.isEmpty {
                emptyState
            } else {
                gallery
            }
            Divider()
            footer
        }
        .frame(width: 320)
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
            TextField("Search wallpapers", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private var gallery: some View {
        let shown = visibleAssets
        let rows = (shown.count + 1) / 2
        let contentHeight = CGFloat(rows) * 104 + 14
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shown) { asset in
                    AssetTile(
                        asset: asset,
                        thumbnail: state.thumbnails[asset.id],
                        isSelected: state.selectedAssetID == asset.id,
                        downloadProgress: downloader.progress[asset.id],
                        onDelete: asset.isDeletable ? { state.deleteDownload(asset) } : nil
                    ) {
                        if asset.isDownloaded {
                            state.selectedAssetID = asset.id
                            state.wallpaperEnabled = true
                        } else if downloader.progress[asset.id] != nil {
                            downloader.cancel(asset)
                        } else {
                            state.downloadAndSelect(asset)
                        }
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
        .frame(height: min(contentHeight, 420))
        .opacity(state.wallpaperEnabled ? 1 : 0.5)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Only play on power cable", isOn: $state.pausesOnBattery)
            Toggle("Launch at login", isOn: Binding(
                get: { state.launchesAtLogin },
                set: { state.launchesAtLogin = $0 }
            ))
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                preview
                    .frame(width: 132, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
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
        .onHover { isHovering = $0 }
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
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
        } else if let previewURL = asset.previewURL {
            AsyncImage(url: previewURL) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                placeholder
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
