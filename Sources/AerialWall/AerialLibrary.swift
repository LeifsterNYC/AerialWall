import AVFoundation
import AppKit

struct AerialAsset: Identifiable, Hashable {
    let id: String
    let name: String
    let localURL: URL?
    let remoteURL: URL?
    let previewURL: URL?
    let isDeletable: Bool

    var isDownloaded: Bool { localURL != nil }
}

/// Reads Apple's aerial manifest (all ~156 wallpapers with CDN download and
/// preview URLs) and merges it with the videos already on disk — Apple's own
/// downloads plus AerialWall's.
enum AerialLibrary {
    /// Directory for videos downloaded in-app.
    static var downloadsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AerialWall/videos")
    }

    /// (videos directory, manifest file) pairs, newest OS layout first.
    private static var searchLocations: [(videos: URL, manifest: URL?)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tahoe = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
        let legacy = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer")
        return [
            (tahoe.appendingPathComponent("videos"), tahoe.appendingPathComponent("manifest/entries.json")),
            (legacy.appendingPathComponent("4KSDR240FPS"), legacy.appendingPathComponent("entries.json")),
            (downloadsDirectory, nil),
        ]
    }

    static func scan() -> [AerialAsset] {
        let manifest = manifestEntries()
        let localFiles = localVideos()
        var assets: [AerialAsset] = []
        var coveredIDs: Set<String> = []

        for entry in manifest {
            let local = localFiles[entry.id.uppercased()]
            coveredIDs.insert(entry.id.uppercased())
            assets.append(AerialAsset(
                id: entry.id,
                name: entry.name,
                localURL: local?.url,
                remoteURL: entry.videoURL,
                previewURL: entry.previewURL,
                isDeletable: local?.isDeletable ?? false
            ))
        }
        // Local videos missing from the manifest still deserve a tile.
        for (id, local) in localFiles where !coveredIDs.contains(id) {
            assets.append(AerialAsset(
                id: id, name: id, localURL: local.url,
                remoteURL: nil, previewURL: nil, isDeletable: local.isDeletable
            ))
        }
        return assets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct ManifestEntry {
        let id: String
        let name: String
        let videoURL: URL?
        let previewURL: URL?
    }

    private static func manifestEntries() -> [ManifestEntry] {
        for location in searchLocations {
            guard let manifest = location.manifest,
                  let data = try? Data(contentsOf: manifest),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["assets"] as? [[String: Any]], !entries.isEmpty
            else { continue }
            return entries.compactMap { entry in
                guard let id = entry["id"] as? String else { return nil }
                return ManifestEntry(
                    id: id,
                    name: entry["accessibilityLabel"] as? String ?? id,
                    videoURL: (entry["url-4K-SDR-240FPS"] as? String).flatMap(URL.init(string:)),
                    previewURL: (entry["previewImage"] as? String).flatMap(URL.init(string:))
                )
            }
        }
        return []
    }

    private static func localVideos() -> [String: (url: URL, isDeletable: Bool)] {
        let fm = FileManager.default
        var found: [String: (url: URL, isDeletable: Bool)] = [:]
        for location in searchLocations {
            guard let files = try? fm.contentsOfDirectory(at: location.videos, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension.lowercased() == "mov" {
                let id = file.deletingPathExtension().lastPathComponent.uppercased()
                guard found[id] == nil else { continue }
                let isDeletable = fm.isDeletableFile(atPath: file.path)
                    && fm.isWritableFile(atPath: location.videos.path)
                found[id] = (file, isDeletable)
            }
        }
        return found
    }

    static func thumbnail(for asset: AerialAsset) async -> NSImage? {
        guard let localURL = asset.localURL else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: localURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        guard let cgImage = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
