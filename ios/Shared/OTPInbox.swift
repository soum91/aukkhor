import Foundation

/// Reads only the short-lived OTP handoff in Aukkhor's shared app-group
/// container. VaultBridge's password Keychain group is not granted to Aukkhor.
enum OTPInbox {
    private static let group = "group.dev.soum91.aukkhor"
    private static let filename = "otp-inbox-v1.json"

    private struct Envelope: Codable {
        let code: String
        let source: String
        let expiresAt: Date
    }

    static func latestCode() -> String? { read()?.code }

    static func consumeLatest() -> String? {
        guard let envelope = read() else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return envelope.code
    }

    private static func read() -> Envelope? {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        guard envelope.expiresAt > Date() else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return envelope
    }

    private static var fileURL: URL {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group)!
        return directory.appendingPathComponent(filename, isDirectory: false)
    }
}
