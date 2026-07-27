import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if state.assets.isEmpty {
                emptyState
            } else {
                gallery
            }
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("AerialWall").font(.headline)
            Spacer()
            if state.pausesOnBattery && !state.isOnACPower {
                Label("Paused on battery", systemImage: "battery.50percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "mountain.2").font(.largeTitle).foregroundStyle(.secondary)
            Text("No aerials downloaded yet").font(.callout)
            Text("Open System Settings → Wallpaper, pick a Landscape/Cityscape/Underwater/Earth wallpaper, and wait for it to download. Then hit Refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(state.assets) { asset in
                    AssetTile(
                        asset: asset,
                        thumbnail: state.thumbnails[asset.id],
                        isSelected: state.selectedAssetID == asset.id
                    ) {
                        state.selectedAssetID = state.selectedAssetID == asset.id ? "" : asset.id
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 420)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(width: 132, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                )
                Text(asset.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
        .help(asset.name)
    }
}
