import Foundation
import UIKit
import CryptoKit
import Security

enum AukkhorSettings {
    static let group = "group.dev.soum91.aukkhor"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static var host: String {
        get { defaults.string(forKey: "pcHost") ?? "" }
        set { defaults.set(newValue, forKey: "pcHost") }
    }
    static var fingerprint: String {
        get { defaults.string(forKey: "pcFingerprint") ?? "" }
        set { defaults.set(newValue.replacingOccurrences(of: ":", with: "").uppercased(), forKey: "pcFingerprint") }
    }
    static var syncEnabled: Bool {
        get { defaults.bool(forKey: "syncEnabled") }
        set { defaults.set(newValue, forKey: "syncEnabled") }
    }
    static var keyboardClipboardEnabled: Bool {
        get { defaults.bool(forKey: "keyboardClipboardEnabled") }
        set { defaults.set(newValue, forKey: "keyboardClipboardEnabled") }
    }
}

struct AukkhorTrust: Codable {
    let id: String
    let secret: String
}

enum AukkhorError: LocalizedError {
    case invalidSettings, unpaired, badResponse(String), noClipboard, noCode, noKeychain
    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Enter a PC IPv4 address and its complete certificate fingerprint."
        case .unpaired: return "Pair with Windows in the Aukkhor app first."
        case .badResponse(let s): return "Windows: \(s)"
        case .noClipboard: return "The clipboard has no text."
        case .noCode: return "No 4–8 digit one-time code was found."
        case .noKeychain: return "Shared Keychain unavailable. Check app/keyboard entitlements and re-pair."
        }
    }
}

enum AukkhorKeychain {
    private static let account = "windows-trust-v1"
    private static let service = "dev.soum91.aukkhor"

    // Prefer shared group in the full build. Compatibility signers may not provide
    // its entitlement; the containing app then uses the default private Keychain.
    private static var group: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AukkhorKeychainGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    private static func query(useShared: Bool) -> [String: Any] {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if useShared, let group { item[kSecAttrAccessGroup as String] = group }
        return item
    }

    static func load() -> AukkhorTrust? {
        for shared in [true,false] {
            if shared && group == nil { continue }
            var request = query(useShared: shared)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let trust = try? JSONDecoder().decode(AukkhorTrust.self, from: data) {
                return trust
            }
        }
        return nil
    }

    @discardableResult static func save(_ trust: AukkhorTrust) -> Bool {
        guard let data = try? JSONEncoder().encode(trust) else { return false }
        for shared in [true,false] {
            if shared && group == nil { continue }
            let criteria = query(useShared: shared)
            var item = criteria
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemDelete(criteria as CFDictionary)
            let result = SecItemAdd(item as CFDictionary, nil)
            if result == errSecSuccess { return true }
            if result != errSecMissingEntitlement && result != errSecParam { break }
        }
        return false
    }

    static func remove() {
        SecItemDelete(query(useShared: true) as CFDictionary)
        SecItemDelete(query(useShared: false) as CFDictionary)
    }
}

final class PinnedCertificateDelegate: NSObject, URLSessionDelegate {
    let fingerprint: String
    init(fingerprint: String) { self.fingerprint = fingerprint.uppercased() }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let cert = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(cert) as Data)
            .map { String(format: "%02X", $0) }.joined()
        guard digest == fingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

actor AukkhorLink {
    static let shared = AukkhorLink()

    private func endpoint() throws -> URL {
        let host = AukkhorSettings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }),
              AukkhorSettings.fingerprint.range(of: "^[0-9A-F]{64}$", options: .regularExpression) != nil,
              let url = URL(string: "https://\(host):45789") else { throw AukkhorError.invalidSettings }
        return url
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: PinnedCertificateDelegate(fingerprint: AukkhorSettings.fingerprint), delegateQueue: nil)
    }

    private func request(_ path: String, method: String = "GET", token: String? = nil,
                         code: String? = nil, body: Data? = nil) throws -> URLRequest {
        var req = URLRequest(url: try endpoint().appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let code { req.setValue(code, forHTTPHeaderField: "X-Aukkhor-Code") }
        if body != nil { req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        return req
    }

    private func exchange(_ req: URLRequest) async throws -> Data {
        let s = session()
        defer { s.invalidateAndCancel() }
        let (data, response) = try await s.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AukkhorError.badResponse(String(data: data.prefix(512), encoding: .utf8) ?? "Request failed")
        }
        return data
    }

    func pair(code: String) async throws {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw AukkhorError.badResponse("Enter the six-digit code from Windows.")
        }
        let data = try await exchange(request("pair", method: "POST", code: code))
        struct PairResult: Decodable { let id: String; let secret: String }
        let result = try JSONDecoder().decode(PairResult.self, from: data)
        guard result.id.count == 32, result.secret.count == 64,
              AukkhorKeychain.save(AukkhorTrust(id: result.id, secret: result.secret)) else { throw AukkhorError.noKeychain }
    }

    private func sessionToken() async throws -> String {
        guard let known = AukkhorKeychain.load(),
              let key = Data(hex: known.secret) else { throw AukkhorError.unpaired }
        let data = try await exchange(request("challenge"))
        struct Challenge: Decodable { let id: String; let nonce: String }
        let challenge = try JSONDecoder().decode(Challenge.self, from: data)
        guard challenge.id == known.id, challenge.nonce.count == 48 else { throw AukkhorError.badResponse("Trusted PC identity changed") }
        let mac = HMAC<SHA256>.authenticationCode(for: Data(challenge.nonce.utf8), using: SymmetricKey(data: key))
        let proof = Data(mac).map { String(format: "%02X", $0) }.joined()
        var req = try request("reconnect", method: "POST")
        req.setValue(proof, forHTTPHeaderField: "X-Aukkhor-Proof")
        let reply = try await exchange(req)
        guard let token = String(data: reply, encoding: .utf8), token.count == 48 else { throw AukkhorError.badResponse("Invalid session") }
        return token
    }

    func sendClipboard(_ text: String) async throws {
        guard !text.isEmpty else { throw AukkhorError.noClipboard }
        guard text.utf8.count <= 65536 else { throw AukkhorError.badResponse("Clipboard limit: 64 KiB") }
        let token = try await sessionToken()
        _ = try await exchange(request("clipboard", method: "POST", token: token, body: Data(text.utf8)))
    }

    func receiveClipboard() async throws -> String {
        let token = try await sessionToken()
        let reply = try await exchange(request("clipboard", token: token))
        guard reply.count <= 65536, let result = String(data: reply, encoding: .utf8) else {
            throw AukkhorError.badResponse("Invalid Windows clipboard")
        }
        return result
    }

    func windowsPrompt() async throws -> AukkhorTVPrompt {
        let token = try await sessionToken()
        let data = try await exchange(request("prompt", token: token))
        return try JSONDecoder().decode(AukkhorTVPrompt.self, from: data)
    }

    func typeOnWindows(_ text: String, focusedSession: String) async throws {
        guard !text.isEmpty && text.utf8.count <= 8192 && text.count <= 2048,
              focusedSession.range(of: "^[0-9A-F]{24}$", options: .regularExpression) != nil else {
            throw AukkhorError.badResponse("Invalid text or focused Windows field.")
        }
        let token = try await sessionToken()
        var req = try request("type",method:"POST",token:token,body:Data(text.utf8))
        req.setValue(focusedSession, forHTTPHeaderField: "X-Aukkhor-Session")
        _ = try await exchange(req)
    }

    func sendCode(from text: String) async throws -> String {
        guard let code = CodeExtractor.extract(text) else { throw AukkhorError.noCode }
        let token = try await sessionToken()
        _ = try await exchange(request("code", method: "POST", token: token, body: Data(code.utf8)))
        return code
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(); out.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            out.append(byte)
            index = end
        }
        self = out
    }
}

enum CodeExtractor {
    static func extract(_ text: String) -> String? {
        let exp = try! NSRegularExpression(pattern: #"(?<![0-9])[0-9]{4,8}(?![0-9])"#)
        let ns = text as NSString
        let matches = exp.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // Avoid guessing when a message contains several different numerical candidates.
        let candidates = Set(matches.map { ns.substring(with: $0.range) })
        return candidates.count == 1 ? candidates.first : nil
    }
}

