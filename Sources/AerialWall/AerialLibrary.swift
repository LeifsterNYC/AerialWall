import AVFoundation
import AppKit

struct AerialAsset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

/// Finds the aerial videos macOS has already downloaded and maps their
/// UUID filenames to human-readable names via Apple's entries.json manifest.
enum AerialLibrary {
    /// (videos directory, manifest file) pairs, newest OS layout first.
    private static var searchLocations: [(videos: URL, manifest: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tahoe = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
        let legacy = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer")
        return [
            (tahoe.appendingPathComponent("videos"), tahoe.appendingPathComponent("manifest/entries.json")),
            (legacy.appendingPathComponent("4KSDR240FPS"), legacy.appendingPathComponent("entries.json")),
        ]
    }

    static func scan() -> [AerialAsset] {
        let fm = FileManager.default
        var assets: [AerialAsset] = []
        var seenIDs: Set<String> = []
        for location in searchLocations {
            guard let files = try? fm.contentsOfDirectory(at: location.videos, includingPropertiesForKeys: nil) else { continue }
            let names = assetNames(manifest: location.manifest)
            for file in files where file.pathExtension.lowercased() == "mov" {
                let id = file.deletingPathExtension().lastPathComponent
                guard seenIDs.insert(id.uppercased()).inserted else { continue }
                assets.append(AerialAsset(id: id, name: names[id.uppercased()] ?? id, url: file))
            }
        }
        return assets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func assetNames(manifest: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["assets"] as? [[String: Any]] else { return [:] }
        var names: [String: String] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String else { continue }
            if let label = entry["accessibilityLabel"] as? String {
                names[id.uppercased()] = label
            }
        }
        return names
    }

    static func thumbnail(for asset: AerialAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        guard let cgImage = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
