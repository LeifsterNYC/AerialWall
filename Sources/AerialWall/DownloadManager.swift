import Foundation

/// Downloads aerial videos from Apple's CDN into AerialWall's own folder,
/// publishing per-asset progress.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published var progress: [String: Double] = [:]

    var onComplete: ((_ assetID: String) -> Void)?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func download(_ asset: AerialAsset) {
        guard let remoteURL = asset.remoteURL, tasks[asset.id] == nil else { return }
        progress[asset.id] = 0
        let task = session.downloadTask(with: remoteURL)
        task.taskDescription = asset.id
        tasks[asset.id] = task
        task.resume()
    }

    func cancel(_ asset: AerialAsset) {
        tasks[asset.id]?.cancel()
        tasks[asset.id] = nil
        progress[asset.id] = nil
    }

    private func finish(_ assetID: String, didSucceed: Bool) {
        progress[assetID] = nil
        tasks[assetID] = nil
        if didSucceed { onComplete?(assetID) }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let assetID = downloadTask.taskDescription else { return }
        let fraction = Double(totalBytesWritten) / Double(max(totalBytesExpectedToWrite, 1))
        Task { @MainActor in self.progress[assetID] = fraction }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let assetID = downloadTask.taskDescription else { return }
        // The temp file vanishes when this method returns — move it now.
        let fm = FileManager.default
        let destination = AerialLibrary.downloadsDirectory.appendingPathComponent("\(assetID).mov")
        var didSucceed = false
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            didSucceed = true
        } catch {
            NSLog("Failed to store download \(assetID): \(error)")
        }
        Task { @MainActor in self.finish(assetID, didSucceed: didSucceed) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let assetID = task.taskDescription else { return }
        Task { @MainActor in self.finish(assetID, didSucceed: false) }
    }
}
