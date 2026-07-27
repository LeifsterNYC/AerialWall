import AVFoundation
import AppKit

/// Plays looping videos in borderless windows pinned at desktop level,
/// one per screen, behind icons on every Space. Screens can share one video
/// or each have their own; players are created per unique video.
final class WallpaperController {
    private struct PlayerSet {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
    }

    private var windows: [NSWindow] = []
    private var players: [URL: PlayerSet] = [:]
    private var assignments: [String: URL] = [:]
    private var fallbackURL: URL?
    private var screenObserver: Any?
    private var occlusionObserver: Any?

    /// True while at least one wallpaper window is actually visible —
    /// false when fullscreen apps or the lock screen cover every desktop.
    var isDesktopVisible: Bool {
        windows.isEmpty || windows.contains { $0.occlusionState.contains(.visible) }
    }

    var onDesktopVisibilityChange: ((Bool) -> Void)?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWindows()
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow,
                  self.windows.contains(window) else { return }
            self.onDesktopVisibilityChange?(self.isDesktopVisible)
        }
    }

    static func screenID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// `fallback` plays on every screen without an explicit per-screen entry.
    func setVideos(fallback: URL?, perScreen: [String: URL]) {
        fallbackURL = fallback
        assignments = perScreen
        rebuildWindows()
    }

    func play() { players.values.forEach { $0.player.play() } }
    func pause() { players.values.forEach { $0.player.pause() } }

    func clear() {
        setVideos(fallback: nil, perScreen: [:])
    }

    private func url(for screen: NSScreen) -> URL? {
        if let id = Self.screenID(for: screen), let url = assignments[id] {
            return url
        }
        return fallbackURL
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []

        let neededURLs = Set(NSScreen.screens.compactMap { url(for: $0) })
        players = players.filter { neededURLs.contains($0.key) }
        for url in neededURLs where players[url] == nil {
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            players[url] = PlayerSet(player: player, looper: looper)
        }
        guard !players.isEmpty else { return }

        for screen in NSScreen.screens {
            guard let url = url(for: screen), let playerSet = players[url] else { continue }
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.hasShadow = false

            let view = NSView(frame: screen.frame)
            view.wantsLayer = true
            let playerLayer = AVPlayerLayer(player: playerSet.player)
            playerLayer.frame = view.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill
            view.layer?.addSublayer(playerLayer)

            window.contentView = view
            window.orderBack(nil)
            windows.append(window)
        }
    }
}
