import UIKit
import Photos
import Combine

// Event-driven, session-only observation. No polling, networking or image
// decoding in the keyboard. A reopen check catches a screenshot saved while
// iOS temporarily suspended the extension.
@MainActor final class ScreenshotClipboard: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = ScreenshotClipboard()
    @Published private(set) var status = "Screenshot observer is stopped."
    private var context = "keyboard"
    static var enabled: Bool {
        get { AukkhorSettings.defaults.bool(forKey: "autoScreenshotClipboard") }
        set {
            AukkhorSettings.defaults.set(newValue, forKey: "autoScreenshotClipboard")
            if newValue {
                AukkhorSettings.defaults.set(Date(), forKey: "autoScreenshotEnabledAt")
            }
            if !newValue { PendingScreenshotStore.clear() }
        }
    }

    private var active = false
    private var observing = false
    private var busy = false
    private var generation = 0
    private var pending = false
    private var fetchResult: PHFetchResult<PHAsset>?
    private var requestID: PHImageRequestID?
    private let queue = DispatchQueue(label: "dev.soum91.aukkhor.screenshots", qos: .utility)

    func start(context: String = "keyboard") {
        self.context = context
        guard Self.enabled else { stop(); return }
        active = true
        let permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !observing && (permission == .authorized || permission == .limited) {
            observing = true
            status = "Watching for newly saved screenshots (\(context))."
            PHPhotoLibrary.shared().register(self)
        }
        recoverThenCheck()
    }

    // A screenshot notification is delivered only to the foreground app that
    // receives it. Photos often finishes saving the asset after the event, so
    // allow two delayed passes without using an expensive polling loop.
    func screenshotCapturedInForeground() {
        guard active, Self.enabled else { return }
        for delay in [0.8, 2.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.active else { return }
                self.check()
            }
        }
    }

    func stop() {
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        observing = false
        active = false
        generation += 1
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
        busy = false
        pending = false
        fetchResult = nil
        status = "Screenshot observer stopped. Last attempt: " +
            (AukkhorSettings.defaults.string(forKey: "lastScreenshotCopyAttempt") ?? "none")
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.check() }
    }

    private func finish() {
        busy = false
        requestID = nil
        if pending { pending = false; check() }
    }

    private func recoverThenCheck() {
        guard !busy else { pending = true; return }
        busy = true
        generation += 1
        let token = generation
        let revision = UIPasteboard.general.changeCount
        Task { @MainActor [weak self] in
            let item = await PendingScreenshotStore.load()
            guard let self, self.active, self.generation == token else { return }
            if let item, Self.enabled, UIPasteboard.general.changeCount == revision {
                UIPasteboard.general.setData(item.data, forPasteboardType: item.type)
                if UIPasteboard.general.changeCount != revision {
                    AukkhorSettings.defaults.set(item.identifier, forKey: "lastScreenshotCopied")
                    self.status = "Recovered screenshot into clipboard (\(self.context)). Verify by pasting."
                    AukkhorSettings.defaults.set(self.status, forKey: "lastScreenshotCopyAttempt")
                    PendingScreenshotStore.clear()
                }
            }
            self.busy = false
            self.pending = false
            self.check()
        }
    }

    private func check() {
        guard active, Self.enabled else { return }
        let permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard permission == .authorized || permission == .limited else {
            status = "Photos permission unavailable here. Enable Auto screenshots in keyboard Clips to request it locally."
            return
        }
        if busy { pending = true; return }
        busy = true
        generation += 1
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.active, self.busy, self.generation == token else { return }
            self.generation += 1
            if let request = self.requestID { PHImageManager.default().cancelImageRequest(request) }
            self.status = "Screenshot fetch timed out. Reopen the keyboard to retry."
            self.pending = false
            self.finish()
        }
        let enabledAt = AukkhorSettings.defaults.object(forKey: "autoScreenshotEnabledAt") as? Date ?? Date()
        let since = max(enabledAt, Date().addingTimeInterval(-120))
        let clipboardRevision = UIPasteboard.general.changeCount
        queue.async { [weak self] in
            let options = PHFetchOptions()
            options.fetchLimit = 1
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate > %@",
                PHAssetMediaSubtype.photoScreenshot.rawValue, since as NSDate)
            let result = PHAsset.fetchAssets(with: .image, options: options)
            DispatchQueue.main.async {
                guard let self, self.active, self.generation == token else { return }
                self.fetchResult = result
                guard let asset = result.firstObject,
                      asset.localIdentifier != AukkhorSettings.defaults.string(forKey: "lastScreenshotCopied") else {
                    self.finish(); return
                }
                let request = PHImageRequestOptions()
                request.isNetworkAccessAllowed = false
                request.isSynchronous = false
                request.version = .current
                request.deliveryMode = .highQualityFormat
                self.requestID = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: request) {
                    [weak self] data, type, _, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    guard !degraded else { return }
                    Task { @MainActor in
                        guard let self, self.active, self.generation == token else { return }
                        defer { self.finish() }
                        guard Self.enabled else { return }
                        guard let data, !data.isEmpty, let type else {
                            self.status = "Screenshot found, but Photos did not supply local image data."
                            return
                        }
                        guard data.count <= 12 * 1024 * 1024 else {
                            self.status = "Screenshot skipped: image exceeds 12 MB."
                            return
                        }
                        guard UIPasteboard.general.changeCount == clipboardRevision else {
                            self.status = "Screenshot skipped: clipboard changed during image loading."
                            return
                        }
                        do {
                            try await PendingScreenshotStore.save(data, type: type, identifier: asset.localIdentifier,
                                                                  created: asset.creationDate ?? Date())
                        } catch {
                            self.status = "Screenshot cache failed: \(error.localizedDescription)"
                        }
                        guard self.active, self.generation == token, Self.enabled,
                              UIPasteboard.general.changeCount == clipboardRevision else { return }
                        // Preserve the compressed original without decoding a
                        // full-resolution screenshot into extension memory.
                        UIPasteboard.general.setData(data, forPasteboardType: type)
                        let changed = UIPasteboard.general.changeCount != clipboardRevision
                        self.status = "\(Date().formatted(date: .omitted, time: .standard)) (\(self.context)): " +
                            (changed ? "clipboard revision changed; verify by pasting the image."
                                     : "clipboard write was not confirmed; will retry when reopened.")
                        AukkhorSettings.defaults.set(self.status, forKey: "lastScreenshotCopyAttempt")
                        if changed {
                            AukkhorSettings.defaults.set(asset.localIdentifier, forKey: "lastScreenshotCopied")
                            PendingScreenshotStore.clear()
                        }
                    }
                }
            }
        }
    }
}
