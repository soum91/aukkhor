import Foundation
import UIKit
import CryptoKit
import Security

/// Separate Android TV pairing. Independent from the Windows certificate and keychain identity.
enum AukkhorTVSettings {
    static var host: String {
        get { UserDefaults.standard.string(forKey: "tvHost") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tvHost") }
    }
    static var fingerprint: String {
        get { UserDefaults.standard.string(forKey: "tvFingerprint") ?? "" }
        set { UserDefaults.standard.set(newValue.replacingOccurrences(of: ":", with: "").uppercased(), forKey: "tvFingerprint") }
    }
    static var promptEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "tvPromptEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "tvPromptEnabled") }
    }
}

struct AukkhorTVPrompt: Codable, Identifiable {
    let active: Bool
    let session: String
    let label: String
    var id: String { session }
}

private enum TVTrustKeychain {
    private static let service = "dev.soum91.aukkhor.tv"
    private static let account = "android-tv-trust-v1"
    // App-only Keychain item: no shared entitlement or App Group required.
    static func load() -> AukkhorTrust? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AukkhorTrust.self, from: data)
    }

    static func save(_ trust: AukkhorTrust) -> Bool {
        guard let data = try? JSONEncoder().encode(trust) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

private final class TVCertificateDelegate: NSObject, URLSessionDelegate {
    private let fingerprint: String
    init(_ fingerprint: String) { self.fingerprint = fingerprint }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let cert = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(cert) as Data)
            .map { String(format: "%02X", $0) }.joined()
        completionHandler(digest == fingerprint ? .useCredential : .cancelAuthenticationChallenge,
                          digest == fingerprint ? URLCredential(trust: trust) : nil)
    }
}

/// Authenticated HTTP/1.1 over certificate-pinned LAN TLS. Never transmits normal keyboard input,
/// only text explicitly submitted inside the remote-typing sheet.
actor AukkhorTVLink {
    static let shared = AukkhorTVLink()

    private func endpoint(_ path: String) throws -> URL {
        let host = AukkhorTVSettings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = host.split(separator: ".")
        guard pieces.count == 4,
              pieces.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }),
              AukkhorTVSettings.fingerprint.range(of: "^[0-9A-F]{64}$", options: .regularExpression) != nil,
              let url = URL(string: "https://\(host):45790/\(path)") else {
            throw AukkhorError.invalidSettings
        }
        return url
    }
    private func exchange(_ path: String, method: String = "GET", token: String? = nil,
                          extra: [String:String] = [:], body: Data? = nil) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 7
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config,
                                 delegate: TVCertificateDelegate(AukkhorTVSettings.fingerprint),
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = method
        request.httpBody = body
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (key,value) in extra { request.setValue(value, forHTTPHeaderField: key) }
        if body != nil { request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let (data,response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw AukkhorError.badResponse(String(data: data.prefix(200), encoding: .utf8) ?? "TV request rejected")
        }
        return data
    }

    func pair(code: String) async throws {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw AukkhorError.badResponse("Enter the six digits displayed on the TV.")
        }
        let data = try await exchange("pair", method: "POST", extra: ["X-Aukkhor-Code":code])
        let trust = try JSONDecoder().decode(AukkhorTrust.self, from: data)
        guard trust.id.count == 32 && trust.secret.count == 64 && TVTrustKeychain.save(trust) else {
            throw AukkhorError.noKeychain
        }
    }

    func forget() { TVTrustKeychain.clear() }

    private func sessionToken() async throws -> String {
        guard let trust = TVTrustKeychain.load(),
              let secret = Data(hex: trust.secret) else { throw AukkhorError.unpaired }
        struct Challenge: Decodable { let id: String; let nonce: String }
        let challenge = try JSONDecoder().decode(Challenge.self, from: try await exchange("challenge"))
        guard challenge.id == trust.id && challenge.nonce.count == 48 else {
            throw AukkhorError.badResponse("Android TV identity changed. Pair again.")
        }
        let digest = HMAC<SHA256>.authenticationCode(for: Data(challenge.nonce.utf8),
                                                      using: SymmetricKey(data: secret))
        let proof = Data(digest).map { String(format: "%02X", $0) }.joined()
        let data = try await exchange("reconnect", method: "POST", extra: ["X-Aukkhor-Proof":proof])
        guard let token = String(data: data, encoding: .utf8), token.count == 48 else {
            throw AukkhorError.badResponse("TV returned an invalid session.")
        }
        return token
    }

    func prompt() async throws -> AukkhorTVPrompt {
        let token = try await sessionToken()
        return try JSONDecoder().decode(AukkhorTVPrompt.self,
                                        from: try await exchange("prompt",token: token))
    }

    func type(_ text: String, session target: String) async throws {
        guard !text.isEmpty && text.utf8.count <= 8192 && text.count <= 2048 else {
            throw AukkhorError.badResponse("Enter 1–2048 characters.")
        }
        let token = try await sessionToken()
        _ = try await exchange("type",method:"POST",token:token,
                               extra:["X-Aukkhor-Session":target],body:Data(text.utf8))
    }
}
