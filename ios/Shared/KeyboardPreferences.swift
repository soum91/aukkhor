import Foundation
import UIKit

enum KeyboardPreset: String, CaseIterable, Identifiable {
    case system, midnight, fullBlack, liquidGlass, blossom, mint, sunset, highContrast, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .midnight: return "Midnight"
        case .fullBlack: return "Full Black"
        case .liquidGlass: return "Liquid Glass"
        case .blossom: return "Blossom"
        case .mint: return "Mint"
        case .sunset: return "Sunset"
        case .highContrast: return "High contrast"
        case .custom: return "Custom"
        }
    }
}

enum KeyboardPreferences {
    private static var data: UserDefaults { AukkhorSettings.defaults }
    static var preset: KeyboardPreset {
        get { KeyboardPreset(rawValue: data.string(forKey: "keyboardPreset") ?? "system") ?? .system }
        set { data.set(newValue.rawValue, forKey: "keyboardPreset") }
    }
    static var customAccent: String {
        get { data.string(forKey: "keyboardAccent") ?? "#5B37B0" }
        set { data.set(newValue, forKey: "keyboardAccent") }
    }
    static var cornerRadius: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardCornerRadius") as? Double ?? 7) }
        set { data.set(Double(newValue), forKey: "keyboardCornerRadius") }
    }
    static var haptics: Bool {
        get { data.object(forKey: "keyboardHaptics") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardHaptics") }
    }
    static var keycapStyle: Int {
        get { data.object(forKey: "keyboardKeycapStyle") as? Int ?? 0 }
        set { data.set(max(0, min(2, newValue)), forKey: "keyboardKeycapStyle") }
    }
    static var keySounds: Bool {
        get { data.bool(forKey: "keyboardKeySounds") }
        set { data.set(newValue, forKey: "keyboardKeySounds") }
    }
    static var numberRow: Bool {
        get { data.bool(forKey: "keyboardNumberRow") }
        set { data.set(newValue, forKey: "keyboardNumberRow") }
    }
    static var suggestions: Bool {
        get { data.object(forKey: "keyboardSuggestions") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardSuggestions") }
    }
    static var autocorrect: Bool {
        get { data.bool(forKey: "keyboardAutocorrect") }
        set { data.set(newValue, forKey: "keyboardAutocorrect") }
    }
    static var autoCapitalize: Bool {
        get { data.object(forKey: "keyboardAutoCaps") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardAutoCaps") }
    }
    static var doubleSpacePeriod: Bool {
        get { data.object(forKey: "keyboardDoubleSpace") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardDoubleSpace") }
    }
    static var experimentalGlide: Bool {
        get { data.bool(forKey: "keyboardGlide") }
        set { data.set(newValue, forKey: "keyboardGlide") }
    }

    private static var backgroundFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AukkhorSettings.group)?
            .appendingPathComponent("keyboard-background.jpg")
    }
    static var backgroundImage: UIImage? {
        guard let url = backgroundFile, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    static func setBackgroundImage(_ image: UIImage) throws {
        guard let url = backgroundFile else {
            throw NSError(domain: "AukkhorTheme", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group isn't available. Check signing entitlements."])
        }
        let side: CGFloat = 1200
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale),
                          height: max(1, image.size.height * scale))
        let render = UIGraphicsImageRenderer(size: size)
        let resized = render.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.78) else {
            throw NSError(domain: "AukkhorTheme", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't encode selected photo."])
        }
        try data.write(to: url, options: .atomic)
    }
    static func removeBackgroundImage() throws {
        if let url = backgroundFile, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

extension UIColor {
    convenience init(keyboardHex: String) {
        let input = keyboardHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var number: UInt64 = 0
        guard input.count == 6, Scanner(string: input).scanHexInt64(&number) else {
            self.init(red: 0.36, green: 0.22, blue: 0.69, alpha: 1)
            return
        }
        self.init(red: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255,
                  blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}

struct KeyboardPalette {
    let background: UIColor
    let key: UIColor
    let secondaryKey: UIColor
    let foreground: UIColor
    let muted: UIColor
    let accent: UIColor
    let border: UIColor

    static func selected(dark: Bool) -> KeyboardPalette {
        let palette = KeyboardPreferences.preset
        switch palette {
        case .system:
            return .init(background: .secondarySystemBackground, key: .tertiarySystemBackground,
                         secondaryKey: .systemGray4, foreground: .label, muted: .secondaryLabel,
                         accent: .systemIndigo, border: .separator)
        case .midnight:
            return .init(background: UIColor(keyboardHex: "#101728"), key: UIColor(keyboardHex: "#27344D"),
                         secondaryKey: UIColor(keyboardHex: "#394769"), foreground: .white,
                         muted: UIColor(keyboardHex: "#B3C0DF"), accent: UIColor(keyboardHex: "#91A8FF"),
                         border: UIColor(keyboardHex: "#546482"))
        case .fullBlack:
            return .init(background: .black, key: UIColor(keyboardHex: "#111111"),
                         secondaryKey: UIColor(keyboardHex: "#202020"), foreground: .white,
                         muted: UIColor(keyboardHex: "#A0A0A0"), accent: .white,
                         border: UIColor(keyboardHex: "#333333"))
        case .liquidGlass:
            return .init(background: UIColor(keyboardHex: "#11131A"), key: UIColor(keyboardHex: "#353B48"),
                         secondaryKey: UIColor(keyboardHex: "#4C5362"), foreground: .white,
                         muted: UIColor(keyboardHex: "#D0D6E0"), accent: UIColor(keyboardHex: "#B4D8FF"),
                         border: UIColor(keyboardHex: "#8994A8"))
        case .blossom:
            return .init(background: UIColor(keyboardHex: "#FFF0F5"), key: UIColor(keyboardHex: "#FFFFFF"),
                         secondaryKey: UIColor(keyboardHex: "#F8CEDB"), foreground: UIColor(keyboardHex: "#4B3041"),
                         muted: UIColor(keyboardHex: "#8A6277"), accent: UIColor(keyboardHex: "#CD5485"),
                         border: UIColor(keyboardHex: "#E6ABBF"))
        case .mint:
            return .init(background: UIColor(keyboardHex: "#DCEFE9"), key: .white,
                         secondaryKey: UIColor(keyboardHex: "#AFE0CF"), foreground: UIColor(keyboardHex: "#163D34"),
                         muted: UIColor(keyboardHex: "#447667"), accent: UIColor(keyboardHex: "#16765E"),
                         border: UIColor(keyboardHex: "#84B9A6"))
        case .sunset:
            return .init(background: UIColor(keyboardHex: "#3D2145"), key: UIColor(keyboardHex: "#634064"),
                         secondaryKey: UIColor(keyboardHex: "#8B5067"), foreground: .white,
                         muted: UIColor(keyboardHex: "#F1C5CB"), accent: UIColor(keyboardHex: "#FFC071"),
                         border: UIColor(keyboardHex: "#9D718F"))
        case .highContrast:
            return .init(background: .black, key: UIColor(keyboardHex: "#202020"),
                         secondaryKey: UIColor(keyboardHex: "#393939"), foreground: .white,
                         muted: .white, accent: .yellow, border: .white)
        case .custom:
            let accent = UIColor(keyboardHex: KeyboardPreferences.customAccent)
            return .init(background: dark ? UIColor(keyboardHex: "#202126") : UIColor(keyboardHex: "#E8E9EF"),
                         key: dark ? UIColor(keyboardHex: "#35363C") : .white,
                         secondaryKey: dark ? UIColor(keyboardHex: "#484953") : UIColor(keyboardHex: "#CFD0DE"),
                         foreground: dark ? .white : .black,
                         muted: dark ? .lightGray : .darkGray,
                         accent: accent, border: accent.withAlphaComponent(0.5))
        }
    }
}

