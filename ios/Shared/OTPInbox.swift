import Foundation

/// Reads only temporary SMS codes and generated TOTP codes from Aukkhor's
/// shared app-group container. VaultBridge's password Keychain group is not granted.
enum OTPInbox {
    private static let group = "group.dev.soum91.aukkhor"

    struct Candidate {
        let title: String
        let code: String
        let expiresAt: Date
        let temporarySMS: Bool
    }

    private struct Envelope: Codable {
        let code: String
        let source: String
        let expiresAt: Date
    }

    private struct CachedTOTP: Codable {
        let id: UUID
        let issuer: String
        let accountName: String
        let service: String
        let code: String
        let expiresAt: Date
    }

    static func availableCandidates(at date: Date = Date()) -> [Candidate] {
        var candidates: [Candidate] = []
        if let sms = readSMS(), sms.expiresAt > date {
            candidates.append(Candidate(title: "SMS", code: sms.code,
                                        expiresAt: sms.expiresAt, temporarySMS: true))
        }
        guard let data = try? Data(contentsOf: totpURL),
              let entries = try? JSONDecoder().decode([CachedTOTP].self, from: data) else {
            return candidates
        }
        candidates.append(contentsOf: entries.filter { $0.expiresAt > date }.map {
            Candidate(title: $0.issuer + " · " + $0.accountName, code: $0.code,
                      expiresAt: $0.expiresAt, temporarySMS: false)
        })
        return candidates
    }

    static func consume(_ candidate: Candidate) -> String? {
        guard candidate.expiresAt > Date() else { return nil }
        if candidate.temporarySMS {
            guard let sms = readSMS(), sms.code == candidate.code,
                  sms.expiresAt > Date() else { return nil }
            try? FileManager.default.removeItem(at: smsURL)
        }
        return candidate.code
    }

    private static func readSMS() -> Envelope? {
        guard let data = try? Data(contentsOf: smsURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        guard envelope.expiresAt > Date() else {
            try? FileManager.default.removeItem(at: smsURL)
            return nil
        }
        return envelope
    }

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    private static var smsURL: URL {
        folder!.appendingPathComponent("otp-inbox-v1.json", isDirectory: false)
    }
    private static var totpURL: URL {
        folder!.appendingPathComponent("totp-codes-v1.json", isDirectory: false)
    }
}
