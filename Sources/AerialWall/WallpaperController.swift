import AVFoundation
import AppKit

/// Plays a looping video in borderless windows pinned at desktop level,
/// one per screen, behind icons on every Space.
final class WallpaperController {
    private var windows: [NSWindow] = []
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var screenObserver: Any?

    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWindows()
        }
    }

    func setVideo(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        self.player = player
        rebuildWindows()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    func clear() {
        player?.pause()
        player = nil
        looper = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard let player else { return }

        for screen in NSScreen.screens {
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
            let playerLayer = AVPlayerLayer(player: player)
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
