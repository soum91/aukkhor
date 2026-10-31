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
    static var renderingSignature: String {
        data.dictionaryRepresentation().filter { $0.key.hasPrefix("keyboard") }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    }
    static var preset: KeyboardPreset {
        get { KeyboardPreset(rawValue: data.string(forKey: "keyboardPreset") ?? "system") ?? .system }
        set { data.set(newValue.rawValue, forKey: "keyboardPreset") }
    }
    static var customAccent: String {
        get { data.string(forKey: "keyboardAccent") ?? "#5B37B0" }
        set { data.set(newValue, forKey: "keyboardAccent") }
    }
    static var customBackground: String {
        get { data.string(forKey: "keyboardBackground") ?? "#202126" }
        set { data.set(newValue, forKey: "keyboardBackground") }
    }
    static var customKey: String {
        get { data.string(forKey: "keyboardKey") ?? "#35363C" }
        set { data.set(newValue, forKey: "keyboardKey") }
    }
    static var customSecondaryKey: String {
        get { data.string(forKey: "keyboardSecondaryKey") ?? "#484953" }
        set { data.set(newValue, forKey: "keyboardSecondaryKey") }
    }
    static var customForeground: String {
        get { data.string(forKey: "keyboardForeground") ?? "#FFFFFF" }
        set { data.set(newValue, forKey: "keyboardForeground") }
    }
    static var keyOpacity: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardKeyOpacity") as? Double ?? 0.72) }
        set { data.set(Double(max(0.1, min(1, newValue))), forKey: "keyboardKeyOpacity") }
    }
    static var keySpacing: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardKeySpacing") as? Double ?? 6) }
        set { data.set(Double(max(2, min(10, newValue))), forKey: "keyboardKeySpacing") }
    }
    static var keyHeight: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardKeyHeight") as? Double ?? 43) }
        set { data.set(Double(max(36, min(56, newValue))), forKey: "keyboardKeyHeight") }
    }
    static var oneHandSide: Int {
        get { data.integer(forKey: "keyboardOneHandSide") }
        set { data.set(max(0, min(2, newValue)), forKey: "keyboardOneHandSide") }
    }
    static var usesGlass: Bool {
        get { data.object(forKey: "keyboardUsesGlass") as? Bool ?? false }
        set { data.set(newValue, forKey: "keyboardUsesGlass") }
    }
    static var glassEnabled: Bool { preset == .liquidGlass || usesGlass }
    static func setGlassEnabled(_ enabled: Bool) {
        usesGlass = enabled
        if !enabled && preset == .liquidGlass { preset = .custom }
    }
    static var clearGlass: Bool {
        get { data.object(forKey: "keyboardClearGlass") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardClearGlass") }
    }
    static var glassTintStrength: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardGlassTint") as? Double ?? 0.08) }
        set { data.set(Double(max(0, min(0.5, newValue))), forKey: "keyboardGlassTint") }
    }
    static var interactiveGlass: Bool {
        get { data.object(forKey: "keyboardInteractiveGlass") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardInteractiveGlass") }
    }
    static var cornerRadius: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardCornerRadius") as? Double ?? 7) }
        set { data.set(Double(newValue), forKey: "keyboardCornerRadius") }
    }
    static var typingHeight: CGFloat {
        // Four typing rows + compact controls/suggestions + gaps/padding.
        // iOS owns its bottom globe/safe-area strip; do not duplicate that row.
        keyHeight * 4 + 48 + (numberRow ? keyHeight + 6 : 0)
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
        self.data.set(UUID().uuidString, forKey: "keyboardPhotoRevision")
    }
    static func removeBackgroundImage() throws {
        if let url = backgroundFile, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        data.set(UUID().uuidString, forKey: "keyboardPhotoRevision")
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
            return .init(background: UIColor(keyboardHex: KeyboardPreferences.customBackground),
                         key: UIColor(keyboardHex: KeyboardPreferences.customKey),
                         secondaryKey: UIColor(keyboardHex: KeyboardPreferences.customSecondaryKey),
                         foreground: UIColor(keyboardHex: KeyboardPreferences.customForeground),
                         muted: UIColor(keyboardHex: KeyboardPreferences.customForeground).withAlphaComponent(0.7),
                         accent: accent, border: accent.withAlphaComponent(0.5))
        }
    }
}


// The canvas material is independent of keycap rendering. No opaque layer is
// placed behind this effect, so clear glass can sample the available backdrop.
@MainActor enum KeyboardCanvasAppearance {
    static func apply(to effectView: UIVisualEffectView, surface: UIView,
                      palette: KeyboardPalette,
                      reducedTransparency: Bool = UIAccessibility.isReduceTransparencyEnabled) {
        effectView.isHidden = false // Keys live in its contentView, even with glass off.
        effectView.alpha = 1
        effectView.backgroundColor = .clear
        effectView.contentView.backgroundColor = .clear
        effectView.isUserInteractionEnabled = true
        guard KeyboardPreferences.glassEnabled, !reducedTransparency else {
            effectView.effect = nil
            surface.backgroundColor = palette.background
            return
        }
        surface.backgroundColor = .clear
        if #available(iOS 26.0, *) {
            let material = UIGlassEffect(style: KeyboardPreferences.clearGlass ? .clear : .regular)
            material.isInteractive = KeyboardPreferences.interactiveGlass
            let tint = KeyboardPreferences.glassTintStrength
            material.tintColor = tint > 0 ? palette.accent.withAlphaComponent(tint) : nil
            effectView.effect = material
        } else {
            effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
    }
}

// Used by every key, including Space, actions and suggestion candidates.
enum KeyboardKeyAppearance {
    static func apply(to button: UIButton, palette: KeyboardPalette, secondary: Bool = false) {
        button.subviews.filter { $0.tag == 9401 }.forEach { $0.removeFromSuperview() }
        button.backgroundColor = .clear
        button.layer.borderWidth = 0
        button.layer.shadowOpacity = 0
        button.layer.cornerRadius = KeyboardPreferences.cornerRadius
        guard KeyboardPreferences.keycapStyle != 2 else { return }
        let color = secondary ? palette.secondaryKey : palette.key
        let glass = KeyboardPreferences.preset == .liquidGlass || KeyboardPreferences.usesGlass
        if glass && !UIAccessibility.isReduceTransparencyEnabled {
            let effect: UIVisualEffect
            if #available(iOS 26.0, *) {
                let material = UIGlassEffect(style: .regular)
                material.isInteractive = true
                material.tintColor = color.withAlphaComponent(KeyboardPreferences.keyOpacity)
                effect = material
            } else {
                effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            let backdrop = UIVisualEffectView(effect: effect)
            backdrop.tag = 9401
            backdrop.isUserInteractionEnabled = false
            backdrop.frame = button.bounds
            backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backdrop.layer.cornerRadius = KeyboardPreferences.cornerRadius
            backdrop.clipsToBounds = true
            button.insertSubview(backdrop, at: 0)
        } else {
            button.backgroundColor = color.withAlphaComponent(KeyboardPreferences.keyOpacity)
        }
        if KeyboardPreferences.keycapStyle == 0 {
            button.layer.borderWidth = glass ? 0.5 : 0.25
            button.layer.borderColor = palette.border.withAlphaComponent(0.4).cgColor
        }
    }
}

// UIButton can insert its image view lazily during layout. Keep the material
// beneath both label and symbol even after UIKit rebuilds those subviews.
final class KeyboardButton: UIButton {
    override var isHighlighted: Bool {
        didSet { if oldValue != isHighlighted { alpha = isHighlighted ? 0.65 : 1 } }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let backdrop = subviews.first(where: { $0.tag == 9401 }), subviews.first !== backdrop {
            sendSubviewToBack(backdrop)
        }
    }
}

// UIKit asks this view for its own height when embedding it in the keyboard
// presentation. A generic controller view leaves UIKit to guess that height.
final class KeyboardInputView: UIInputView {
    var contentHeight: CGFloat = KeyboardPreferences.typingHeight {
        didSet {
            if abs(oldValue - contentHeight) > 0.5 { invalidateIntrinsicContentSize() }
        }
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { fittedSize(size) }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize { fittedSize(targetSize) }
    override func systemLayoutSizeFitting(_ targetSize: CGSize,
                                          withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize { fittedSize(targetSize) }
    private func fittedSize(_ target: CGSize) -> CGSize {
        let width = target.width > 0 && target.width < 10000 ? target.width : bounds.width
        return CGSize(width: width, height: contentHeight)
    }
}
