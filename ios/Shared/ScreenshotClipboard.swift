import UIKit
import Photos

// Event-driven, session-only observation. No polling, networking or image
// decoding in the keyboard. A reopen check catches a screenshot saved while
// iOS temporarily suspended the extension.
@MainActor final class ScreenshotClipboard: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = ScreenshotClipboard()
    static var enabled: Bool {
        get { AukkhorSettings.defaults.bool(forKey: "autoScreenshotClipboard") }
        set {
            AukkhorSettings.defaults.set(newValue, forKey: "autoScreenshotClipboard")
            if newValue {
                AukkhorSettings.defaults.set(Date(), forKey: "autoScreenshotEnabledAt")
            }
        }
    }

    private var active = false
    private var busy = false
    private var generation = 0
    private var pending = false
    private var fetchResult: PHFetchResult<PHAsset>?
    private var requestID: PHImageRequestID?
    private let queue = DispatchQueue(label: "dev.soum91.aukkhor.screenshots", qos: .utility)

    func start() {
        guard Self.enabled else { stop(); return }
        let permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard permission == .authorized || permission == .limited else { stop(); return }
        if !active {
            active = true
            PHPhotoLibrary.shared().register(self)
        }
        check()
    }

    func stop() {
        if active { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        active = false
        generation += 1
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
        busy = false
        pending = false
        fetchResult = nil
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.check() }
    }

    private func finish() {
        busy = false
        requestID = nil
        if pending { pending = false; check() }
    }

    private func check() {
        guard active, Self.enabled else { return }
        if busy { pending = true; return }
        busy = true
        let token = generation
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
                        guard Self.enabled, let data, !data.isEmpty,
                              data.count <= 12 * 1024 * 1024, let type,
                              UIPasteboard.general.changeCount == clipboardRevision else { return }
                        // Preserve the compressed original without decoding a
                        // full-resolution screenshot into extension memory.
                        UIPasteboard.general.setData(data, forPasteboardType: type)
                        AukkhorSettings.defaults.set(asset.localIdentifier, forKey: "lastScreenshotCopied")
                    }
                }
            }
        }
    }
}
