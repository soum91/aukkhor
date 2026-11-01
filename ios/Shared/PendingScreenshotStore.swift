import Foundation

// One bounded recovery item, never a screenshot history. Disk work runs away
// from typing. The shared App Group lets the keyboard recover a background
// clipboard write that iOS rejected in the containing app.
@MainActor enum PendingScreenshotStore {
    struct Item {
        let data: Data
        let type: String
        let identifier: String
    }
    private static var directory: URL {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AukkhorSettings.group)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("ScreenshotRecovery", isDirectory: true)
    }
    static func isFresh(_ created: Date, enabledAt: Date, now: Date = Date()) -> Bool {
        created > enabledAt && now.timeIntervalSince(created) >= 0 && now.timeIntervalSince(created) <= 120
    }
    private static func safeURL(_ filename: String, in folder: URL) -> URL? {
        guard filename.hasPrefix("screenshot-"), filename.hasSuffix(".bin"), !filename.contains("/"),
              !filename.contains("..") else { return nil }
        return folder.appendingPathComponent(filename)
    }
    static func save(_ data: Data, type: String, identifier: String, created: Date) async throws {
        guard ScreenshotClipboard.enabled, data.count <= 12 * 1024 * 1024 else { return }
        let defaults = AukkhorSettings.defaults
        let folder = directory
        let filename = "screenshot-\(UUID().uuidString).bin"
        let url = folder.appendingPathComponent(filename)
        let previous = defaults.string(forKey: "pendingScreenshotFile").flatMap { safeURL($0, in: folder) }
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            if let previous { try? FileManager.default.removeItem(at: previous) }
        }.value
        guard ScreenshotClipboard.enabled else {
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }
            return
        }
        defaults.set(type, forKey: "pendingScreenshotType")
        defaults.set(identifier, forKey: "pendingScreenshotIdentifier")
        defaults.set(created, forKey: "pendingScreenshotCreated")
        defaults.set(filename, forKey: "pendingScreenshotFile")
    }
    static func load() async -> Item? {
        let defaults = AukkhorSettings.defaults
        guard let created = defaults.object(forKey: "pendingScreenshotCreated") as? Date,
              let enabled = defaults.object(forKey: "autoScreenshotEnabledAt") as? Date,
              isFresh(created, enabledAt: enabled),
              let identifier = defaults.string(forKey: "pendingScreenshotIdentifier"),
              identifier != defaults.string(forKey: "lastScreenshotCopied"),
              let type = defaults.string(forKey: "pendingScreenshotType"),
              let filename = defaults.string(forKey: "pendingScreenshotFile"),
              let url = safeURL(filename, in: directory) else { return nil }
        let data: Data? = await Task.detached(priority: .utility) { () -> Data? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= 12 * 1024 * 1024 else { return nil }
            return try? Data(contentsOf: url)
        }.value
        guard let data, defaults.string(forKey: "pendingScreenshotFile") == filename else { return nil }
        return Item(data: data, type: type, identifier: identifier)
    }
    static func clear() {
        let defaults = AukkhorSettings.defaults
        let url = defaults.string(forKey: "pendingScreenshotFile").flatMap { safeURL($0, in: directory) }
        for key in ["pendingScreenshotFile", "pendingScreenshotType", "pendingScreenshotIdentifier", "pendingScreenshotCreated"] {
            defaults.removeObject(forKey: key)
        }
        if let url { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) } }
    }
}
