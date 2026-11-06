import Foundation
import UIKit

enum KeyboardPreset: String, CaseIterable, Identifiable {
    case system, midnight, fullBlack, liquidGlass, clearPrism, blossom, mint, sunset, highContrast, custom

    // Clear Prism's live backdrop caused severe missed input on devices. Keep
    // its raw value only to migrate existing installations; never offer it as
    // a selectable rendering mode again.
    static var allCases: [KeyboardPreset] {
        [.system, .midnight, .fullBlack, .liquidGlass, .blossom, .mint,
         .sunset, .highContrast, .custom]
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .midnight: return "Midnight"
        case .fullBlack: return "Full Black"
        case .liquidGlass: return "Liquid Glass"
        case .clearPrism: return "Clear Prism"
        case .blossom: return "Blossom"
        case .mint: return "Mint"
        case .sunset: return "Sunset"
        case .highContrast: return "High contrast"
        case .custom: return "Custom"
        }
    }
}

enum KeyboardHapticMode: Int, CaseIterable {
    case impact, selection, vibration

    var title: String {
        switch self {
        case .impact: return "Light"
        case .selection: return "Selection"
        case .vibration: return "Vibrate"
        }
    }

    var next: KeyboardHapticMode {
        KeyboardHapticMode(rawValue: (rawValue + 1) % Self.allCases.count) ?? .impact
    }
}

enum KeyboardPreferences {
    private static var data: UserDefaults { AukkhorSettings.defaults }
    static var renderingSignature: String {
        data.dictionaryRepresentation().filter { $0.key.hasPrefix("keyboard") }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    }
    static var preset: KeyboardPreset {
        get {
            let saved = KeyboardPreset(rawValue: data.string(forKey: "keyboardPreset") ?? "system") ?? .system
            guard saved == .clearPrism else { return saved }
            // The keyboard can retain its theme across IPA updates. Migrate
            // before the first draw so the heavy effect cannot return after
            // installing this version, even if the old Glass toggle was on.
            data.set(KeyboardPreset.system.rawValue, forKey: "keyboardPreset")
            data.set(false, forKey: "keyboardUsesGlass")
            data.set(true, forKey: "keyboardSeamlessBackground")
            data.set(false, forKey: "keyboardClearGlass")
            return .system
        }
        set { data.set((newValue == .clearPrism ? .system : newValue).rawValue, forKey: "keyboardPreset") }
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
    // A hit-area setting, not touch pressure. Cache it on views when the keys
    // are built so the touch path never reads UserDefaults for each finger.
    static var touchExpansion: CGFloat {
        get { CGFloat(max(0, min(16, data.object(forKey: "keyboardTouchExpansion") as? Double ?? 10))) }
        set { data.set(Double(max(0, min(16, newValue))), forKey: "keyboardTouchExpansion") }
    }
    static let touchExpansionSteps: [CGFloat] = [0, 6, 10, 14, 16]
    static func increaseTouchExpansion() {
        let current = touchExpansion
        touchExpansion = touchExpansionSteps.first(where: { $0 > current }) ?? touchExpansionSteps[0]
    }
    // The remote keyboard can bypass UIButton's delayed tracking for character
    // keys. Keep a switch so a user can revert to the old touch path instantly
    // if their iOS build handles UIControl events more reliably.
    static var directTouchRouting: Bool {
        get { data.object(forKey: "keyboardDirectTouchRouting") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardDirectTouchRouting") }
    }
    static var keyHeight: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardKeyHeight") as? Double ?? 43) }
        set { data.set(Double(max(36, min(56, newValue))), forKey: "keyboardKeyHeight") }
    }
    static var heightScale: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardHeightScale") as? Double ?? 0.9) }
        set { data.set(Double(max(0.85, min(1.15, newValue))), forKey: "keyboardHeightScale") }
    }
    static var rowHeight: CGFloat { (keyHeight * heightScale).rounded() }
    static let rowGap: CGFloat = 4
    static var oneHandSide: Int {
        get { data.integer(forKey: "keyboardOneHandSide") }
        set { data.set(max(0, min(2, newValue)), forKey: "keyboardOneHandSide") }
    }
    static var usesGlass: Bool {
        get { data.object(forKey: "keyboardUsesGlass") as? Bool ?? false }
        set { data.set(newValue, forKey: "keyboardUsesGlass") }
    }
    static var glassEnabled: Bool { preset == .liquidGlass || preset == .clearPrism || usesGlass }
    static var seamlessBackground: Bool {
        get { data.object(forKey: "keyboardSeamlessBackground") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardSeamlessBackground") }
    }
    static var usesSystemCanvas: Bool {
        preset != .clearPrism && seamlessBackground && (preset == .system || glassEnabled)
    }
    static func setGlassEnabled(_ enabled: Bool) {
        usesGlass = enabled
        if !enabled && (preset == .liquidGlass || preset == .clearPrism) { preset = .custom }
    }
    static var clearGlass: Bool {
        get { preset == .clearPrism || (data.object(forKey: "keyboardClearGlass") as? Bool ?? false) }
        set { data.set(newValue, forKey: "keyboardClearGlass") }
    }
    static var glassTintStrength: CGFloat {
        get { preset == .clearPrism ? 0 : CGFloat(data.object(forKey: "keyboardGlassTint") as? Double ?? 0.08) }
        set { data.set(Double(max(0, min(0.5, newValue))), forKey: "keyboardGlassTint") }
    }
    static var interactiveGlass: Bool {
        get { preset != .clearPrism && (data.object(forKey: "keyboardInteractiveGlass") as? Bool ?? true) }
        set { data.set(newValue, forKey: "keyboardInteractiveGlass") }
    }
    static var cornerRadius: CGFloat {
        get { CGFloat(data.object(forKey: "keyboardCornerRadius") as? Double ?? 7) }
        set { data.set(Double(newValue), forKey: "keyboardCornerRadius") }
    }
    static var typingHeight: CGFloat {
        // Exact row stack height, with no footer or bottom padding.
        // The system globe strip sits outside this content area.
        let rows: CGFloat = numberRow ? 5 : 4
        return 24 + rows * (rowHeight + rowGap)
    }
    static var haptics: Bool {
        get { data.object(forKey: "keyboardHaptics") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardHaptics") }
    }
    static var hapticMode: KeyboardHapticMode {
        get { KeyboardHapticMode(rawValue: data.integer(forKey: "keyboardHapticMode")) ?? .impact }
        set { data.set(newValue.rawValue, forKey: "keyboardHapticMode") }
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
    // Capitalize the start of sentences, following each field's own
    // capitalization trait (none for URLs, emails and passwords).
    static var autoCapitalize: Bool {
        get { data.object(forKey: "keyboardAutoCaps") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardAutoCaps") }
    }
    static var autocorrect: Bool {
        get { data.bool(forKey: "keyboardAutocorrect") }
        set { data.set(newValue, forKey: "keyboardAutocorrect") }
    }
    static var textReplacement: Bool {
        get { data.object(forKey: "keyboardTextReplacement") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardTextReplacement") }
    }
    static var doubleSpacePeriod: Bool {
        get { data.object(forKey: "keyboardDoubleSpace") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardDoubleSpace") }
    }
    // iOS-style enlarged letter above the pressed key.
    static var keyPopups: Bool {
        get { data.object(forKey: "keyboardKeyPopups") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardKeyPopups") }
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
        seamlessBackground = false
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
        case .clearPrism:
            return .init(background: .clear, key: .white, secondaryKey: .white,
                         foreground: .white, muted: UIColor.white.withAlphaComponent(0.7),
                         accent: .white, border: .white)
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
        // This view is decoration only. Controls live in a plain sibling above
        // it so UIKit's private glass/backdrop views can never swallow taps.
        effectView.isUserInteractionEnabled = false
        // UIKit already paints the keyboard plate, including the globe area.
        // A second, rounded material confined to the extension creates a seam.
        let systemCanvas = KeyboardPreferences.usesSystemCanvas
        surface.layer.cornerRadius = systemCanvas ? 0 : 20
        effectView.layer.cornerRadius = systemCanvas ? 0 : 20
        if systemCanvas {
            effectView.effect = nil
            effectView.overrideUserInterfaceStyle = .unspecified
            surface.backgroundColor = .clear
            return
        }
        guard KeyboardPreferences.glassEnabled, !reducedTransparency else {
            effectView.effect = nil
            effectView.overrideUserInterfaceStyle = .unspecified
            surface.backgroundColor = palette.background
            return
        }
        surface.backgroundColor = .clear
        // Match the material's light/dark appearance to the chosen text color.
        // Resolve against the parent so a previous override cannot lock System mode.
        let text = palette.foreground.resolvedColor(with: surface.traitCollection)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if KeyboardPreferences.clearGlass {
            effectView.overrideUserInterfaceStyle = .unspecified
        } else if text.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
            effectView.overrideUserInterfaceStyle = luminance > 0.6 ? .dark : .light
        } else { effectView.overrideUserInterfaceStyle = .unspecified }
        if #available(iOS 26.0, *) {
            let material = UIGlassEffect(style: KeyboardPreferences.clearGlass ? .clear : .regular)
            // The keyboard has dozens of rapid taps but no interactive glass
            // controls. Let UIKit render refraction without running the
            // material's touch animations on the input process.
            material.isInteractive = false
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
        // The shared canvas supplies the refracted material. A live interactive
        // effect for every key is expensive in the keyboard extension process.
        // Simple translucent fills preserve user colors/opacity without adding
        // dozens of independent backdrop captures and touch animations.
        let clearPrism = KeyboardPreferences.preset == .clearPrism
        let opacity = KeyboardPreferences.keyOpacity * (clearPrism ? 0.05 : 1)
        button.backgroundColor = color.withAlphaComponent(opacity)
        if KeyboardPreferences.keycapStyle == 0 {
            button.layer.borderWidth = clearPrism ? 0.35 : (glass ? 0.5 : 0.25)
            button.layer.borderColor = palette.border.withAlphaComponent(clearPrism ? 0.18 : 0.4).cgColor
        }
    }
}

// UIButton can insert its image view lazily during layout. Keep the material
// beneath both label and symbol even after UIKit rebuilds those subviews.
final class KeyboardButton: UIButton {
    // Touch-down insertion is quicker than waiting for a lift. Keep a guard
    // so VoiceOver's touch-up-only activation still works once, not twice.
    var immediateActionTriggered = false
    var insertsOnTouchDown = false
    var touchExpansion: CGFloat = 10
    var usesPressLens = false
    var onHighlightChanged: ((Bool, KeyboardButton) -> Void)?
    // Finger contact often rolls just beyond a narrow key before lifting.
    // Keep that press valid while it remains near the original key.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -touchExpansion, dy: -touchExpansion).contains(point)
    }
    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            // Avoid changing opacity of the entire key/material subtree.
            let pressedAlpha: CGFloat = usesPressLens ? 0.75 : 0.55
            titleLabel?.alpha = isHighlighted ? pressedAlpha : 1
            imageView?.alpha = isHighlighted ? pressedAlpha : 1
            if usesPressLens {
                // Optical enlargement stays inside the transient press lens;
                // the button frame and its neighbors never move or relayout.
                let magnification: CGFloat = isHighlighted ? 1.12 : 1
                let transform = CGAffineTransform(scaleX: magnification, y: magnification)
                titleLabel?.transform = transform
                imageView?.transform = transform
            }
            onHighlightChanged?(isHighlighted, self)
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let backdrop = subviews.first(where: { $0.tag == 9401 }), subviews.first !== backdrop {
            sendSubviewToBack(backdrop)
        }
    }
}

// One light, transient highlight, shared by all keys. The underlying iOS 26+
// clear glass material is the real refractive surface. Never add a permanent
// rainbow border or dozens of live glass views to this keyboard extension.
// Enlarged character shown above a pressed key, like the system keyboard.
// One cheap shape layer and a label: no blur, no animation, no relayout.
final class KeyboardKeyPopupView: UIView {
    private let shape = CAShapeLayer()
    private let label = UILabel()
    private(set) weak var key: KeyboardButton?
    var shownAt: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
        accessibilityElementsHidden = true
        layer.addSublayer(shape)
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.28
        shape.shadowRadius = 2
        shape.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 32)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
    }
    required init?(coder: NSCoder) { nil }

    // keyFrame and limits are in the superview's coordinates.
    func show(for key: KeyboardButton, keyFrame: CGRect, in limits: CGRect, dark: Bool) {
        self.key = key
        label.text = key.title(for: .normal)
        label.textColor = dark ? .white : .black
        let width = max(keyFrame.width + 16, 46)
        let bubbleHeight: CGFloat = 52
        var top = keyFrame.minY - bubbleHeight + 6
        top = max(limits.minY, top)
        var left = keyFrame.midX - width / 2
        left = min(max(limits.minX + 2, left), limits.maxX - width - 2)
        let frame = CGRect(x: left, y: top, width: width, height: keyFrame.maxY - top)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        let bubble = CGRect(x: 0, y: 0, width: width, height: bubbleHeight)
        let stem = CGRect(x: keyFrame.minX - left, y: bubbleHeight - 12,
                          width: keyFrame.width, height: frame.height - bubbleHeight + 12)
        let path = UIBezierPath(roundedRect: bubble, cornerRadius: 10)
        path.append(UIBezierPath(roundedRect: stem, cornerRadius: 6))
        shape.path = path.cgPath
        shape.shadowPath = path.cgPath
        shape.fillColor = (dark ? UIColor(white: 0.42, alpha: 1) : UIColor.white).cgColor
        label.frame = bubble.insetBy(dx: 3, dy: 2)
        CATransaction.commit()
        isHidden = false
    }

    func hide() {
        isHidden = true
        key = nil
    }
}

final class KeyboardPressLensView: UIView {
    private let transparentCore = CAGradientLayer()
    private let specular = CAGradientLayer()
    private let rim = CAShapeLayer()
    private let lowerRefraction = CAGradientLayer()
    private let lowerRefractionMask = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
        // A nearly clear interior over the single iOS glass canvas. No black
        // fill and no always-visible multicolor border around the keyboard.
        transparentCore.colors = [UIColor.white.withAlphaComponent(0.10).cgColor,
                                  UIColor.clear.cgColor,
                                  UIColor.white.withAlphaComponent(0.035).cgColor]
        transparentCore.locations = [0, 0.48, 1]
        transparentCore.startPoint = CGPoint(x: 0.15, y: 0)
        transparentCore.endPoint = CGPoint(x: 0.75, y: 1)
        layer.addSublayer(transparentCore)
        specular.colors = [UIColor.white.withAlphaComponent(0.68).cgColor,
                           UIColor.white.withAlphaComponent(0.08).cgColor,
                           UIColor.white.withAlphaComponent(0.22).cgColor,
                           UIColor.systemTeal.withAlphaComponent(0.36).cgColor]
        specular.locations = [0, 0.30, 0.74, 1]
        specular.startPoint = CGPoint(x: 0, y: 0)
        specular.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(specular)
        rim.fillColor = UIColor.clear.cgColor
        rim.strokeColor = UIColor.white.cgColor
        rim.lineWidth = 1.6
        specular.mask = rim
        // The bottom arc reproduces the magnifying-glass edge in the reference
        // photo: white-to-teal light, not a static RGB/chromatic rainbow.
        lowerRefraction.colors = [UIColor.white.withAlphaComponent(0.20).cgColor,
                                  UIColor.systemTeal.withAlphaComponent(0.72).cgColor,
                                  UIColor.systemCyan.withAlphaComponent(0.55).cgColor,
                                  UIColor.white.withAlphaComponent(0.14).cgColor]
        lowerRefraction.locations = [0, 0.25, 0.72, 1]
        lowerRefraction.startPoint = CGPoint(x: 0, y: 0.5)
        lowerRefraction.endPoint = CGPoint(x: 1, y: 0.5)
        lowerRefractionMask.fillColor = UIColor.clear.cgColor
        lowerRefractionMask.strokeColor = UIColor.white.cgColor
        lowerRefractionMask.lineWidth = 2.5
        lowerRefraction.mask = lowerRefractionMask
        layer.addSublayer(lowerRefraction)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(over keyRect: CGRect) {
        // The specular only appears during a press. It sits behind the touch
        // host, so it cannot block or defer any character insertion.
        frame = keyRect.insetBy(dx: -7, dy: -8)
        isHidden = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transparentCore.frame = bounds
        transparentCore.cornerRadius = bounds.height / 2
        specular.frame = bounds
        rim.frame = bounds
        rim.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                               cornerRadius: bounds.height / 2).cgPath
        lowerRefraction.frame = bounds
        lowerRefractionMask.frame = bounds
        let bottom = UIBezierPath()
        bottom.move(to: CGPoint(x: bounds.width * 0.12, y: bounds.maxY - 3.5))
        bottom.addQuadCurve(to: CGPoint(x: bounds.width * 0.88, y: bounds.maxY - 3.5),
                            controlPoint: CGPoint(x: bounds.midX, y: bounds.maxY + 1))
        lowerRefractionMask.path = bottom.cgPath
        CATransaction.commit()
    }
}

// Fill only the small gaps between keys, without growing or moving their caps.
// Prefer the closest enabled key; never route outside the keyboard's bounds.
final class KeyboardInteractionView: UIView {
    var touchExpansion: CGFloat = 10
    var directTouchRoutingEnabled = false
    // A diagnostic sheet is modal. Never route its button taps into letter
    // keys beneath it, including when the finger lands close to an edge.
    weak var modalOverlay: UIView?
    // Opt-in, memory-only diagnostics. No logging or extra hit testing while
    // the debugger is off, and no key data is written to a shared container.
    var onTouchDiagnostic: ((CGPoint, String?, Int, Int, Bool) -> Void)?

    // One entry per live finger. The UITouch is held weakly: if UIKit never
    // delivers an end/cancel for a finger (the system edge gate can swallow
    // it), the entry is detected as stale instead of blocking the next touch
    // that happens to reuse the same address.
    private final class TrackedTouch {
        weak var touch: UITouch?
        let hasTouch: Bool
        let key: KeyboardButton
        init(touch: UITouch?, key: KeyboardButton) {
            self.touch = touch
            self.hasTouch = touch != nil
            self.key = key
        }
        var isStale: Bool {
            guard hasTouch else { return false }
            guard let touch else { return true }
            return touch.phase == .ended || touch.phase == .cancelled
        }
    }
    private var trackedKeys: [ObjectIdentifier: TrackedTouch] = [:]
    // Touches already pressed and released through the early root path.
    // Edge keys can reach this view 100+ ms late, after the finger lifted;
    // that late touchesBegan must not count as a second press.
    private final class FinishedTouch {
        weak var touch: UITouch?
        let endedAt: TimeInterval
        let at: TimeInterval
        init(touch: UITouch?, endedAt: TimeInterval, at: TimeInterval) {
            self.touch = touch; self.endedAt = endedAt; self.at = at
        }
    }
    private var finishedTouches: [ObjectIdentifier: FinishedTouch] = [:]
    private(set) var lateDuplicateCount = 0
    private(set) var mergedFingerRecoveryCount = 0
    // Distance one touch sample must jump to count as a second finger that
    // iOS merged into the first. Real drift moves a few points per sample.
    var mergedFingerJump: CGFloat = 18
    private(set) var receivedTouchCount = 0
    private(set) var routedTouchCount = 0
    private(set) var staleTouchRecoveryCount = 0
    private(set) var earlyRootRoutedCount = 0
    var activeTouchCount: Int { trackedKeys.count }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let modalOverlay {
            let overlayPoint = modalOverlay.convert(point, from: self)
            if modalOverlay.point(inside: overlayPoint, with: event) {
                return modalOverlay.hitTest(overlayPoint, with: event)
            }
        }
        let target = resolvedHit(at: point, with: event)
        // Receive the finger on this lightweight view, and send the key's
        // touchDown synchronously. Avoid UIKit's UIControl tracking latency
        // inside remote extension hosts. Leave Space with UIKit so its cursor
        // long-press gesture still works, and preserve the menus/tools.
        if directTouchRoutingEnabled, let key = target as? KeyboardButton,
           key.insertsOnTouchDown, key.accessibilityLabel != "Space" {
            return self
        }
        return target
    }

    private func resolvedHit(at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              bounds.contains(point) else { return nil }
        // UIKit already finds direct key hits. Only search nearby keys when
        // the finger actually lands in a gap, not for every touch event.
        let direct = super.hitTest(point, with: event)
        if let key = direct as? UIButton, key.isEnabled,
           key.bounds.contains(key.convert(point, from: self)) { return key }
        var nearest: UIButton?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        // Row edges (left of "a", right of "l", beside Shift/Delete) have
        // inset gaps wider than the hit expansion. The system keyboard types
        // the closest key there instead of dropping the touch, so keep the
        // closest same-row typing key as a fallback.
        var rowFallback: UIButton?
        var rowFallbackDistance = CGFloat.greatestFiniteMagnitude
        func visit(_ parent: UIView) {
            for child in parent.subviews where !child.isHidden && child.alpha > 0.01 && child.isUserInteractionEnabled {
                if child.clipsToBounds && !child.bounds.contains(child.convert(point, from: self)) { continue }
                if let key = child as? UIButton, key.isEnabled {
                    let frame = key.convert(key.bounds, to: self)
                    guard frame.width > 0, frame.height > 0 else { continue }
                    let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
                    let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
                    var distance = dx * dx + dy * dy
                    // In the gap between a character and a control (Delete,
                    // Shift, return), favor the character: a stray Delete
                    // erases a letter, which is worse than one wrong letter.
                    if distance > 0, let control = key as? KeyboardButton,
                       !(control.title(for: .normal)?.count == 1 && control.accessibilityLabel?.count == 1) {
                        distance *= 4
                    }
                    // Use exactly the same acceptance bounds as the key.
                    if dx <= self.touchExpansion && dy <= self.touchExpansion && distance < nearestDistance {
                        nearest = key
                        nearestDistance = distance
                    } else if dy == 0, let typing = key as? KeyboardButton, typing.insertsOnTouchDown,
                              dx <= frame.width * 0.6, dx < rowFallbackDistance {
                        rowFallback = typing
                        rowFallbackDistance = dx
                    }
                } else { visit(child) }
            }
        }
        visit(self)
        return nearest ?? rowFallback ?? direct
    }

    @discardableResult
    func beginDirectKey(at point: CGPoint, event: UIEvent? = nil) -> KeyboardButton? {
        receivedTouchCount += 1
        guard directTouchRoutingEnabled,
              let key = resolvedHit(at: point, with: event) as? KeyboardButton,
              key.insertsOnTouchDown, key.accessibilityLabel != "Space" else { return nil }
        // Every new finger on a key is a new press. A previous press whose
        // touch-up never arrived must not leave the key latched and swallow
        // this one.
        key.immediateActionTriggered = false
        key.isHighlighted = true
        key.sendActions(for: .touchDown)
        routedTouchCount += 1
        return key
    }

    // An ancestor receives touches before UIKit necessarily dispatches them to
    // the keyboard view. Claim that same touch here to avoid the delay seen
    // between root observation and letter delivery on edge keys. The later
    // UIKit touchesBegan reuses the tracked key and cannot insert twice.
    @discardableResult
    func beginTrackedDirectKey(for touchID: ObjectIdentifier, at point: CGPoint,
                               early: Bool = false, event: UIEvent? = nil,
                               touch: UITouch? = nil) -> KeyboardButton? {
        if let finished = finishedTouches[touchID] {
            let now = ProcessInfo.processInfo.systemUptime
            // UIKit reuses UITouch objects, so identity alone is not enough.
            // A late redelivery still carries its original touch-down time,
            // which is no later than when that touch ended; a new finger
            // reusing the object always starts after it.
            if let touch, finished.touch === touch, now - finished.at < 1.5,
               touch.timestamp <= finished.endedAt {
                lateDuplicateCount += 1
                return nil
            }
            finishedTouches.removeValue(forKey: touchID)
        }
        if let existing = trackedKeys[touchID] {
            let sameTouch = touch == nil || existing.touch === touch
            if sameTouch && !existing.isStale { return existing.key }
            // Leftover from a finger whose end never reached us.
            trackedKeys.removeValue(forKey: touchID)
            existing.key.isHighlighted = false
            existing.key.immediateActionTriggered = false
            staleTouchRecoveryCount += 1
        }
        sweepStaleTouches()
        guard let key = beginDirectKey(at: point, event: event) else { return nil }
        trackedKeys[touchID] = TrackedTouch(touch: touch, key: key)
        if early { earlyRootRoutedCount += 1 }
        return key
    }

    func endDirectKey(_ key: KeyboardButton, at point: CGPoint, cancelled: Bool = false) {
        key.isHighlighted = false
        let within = key.point(inside: key.convert(point, from: self), with: nil)
        key.sendActions(for: cancelled ? .touchCancel : (within ? .touchUpInside : .touchUpOutside))
    }

    // Release a tracked finger. Safe to call from both the root monitor and
    // this view's own touch callbacks; only the first call does anything.
    func finishTrackedDirectKey(for touchID: ObjectIdentifier, at point: CGPoint,
                                cancelled: Bool = false) {
        guard let tracked = trackedKeys.removeValue(forKey: touchID) else { return }
        if let touch = tracked.touch {
            let now = ProcessInfo.processInfo.systemUptime
            finishedTouches = finishedTouches.filter { $0.value.touch != nil && now - $0.value.at < 1.5 }
            finishedTouches[touchID] = FinishedTouch(touch: touch, endedAt: touch.timestamp, at: now)
        }
        endDirectKey(tracked.key, at: point, cancelled: cancelled)
    }

    // iOS sometimes reports a second finger landing right beside the first as
    // the first touch jumping onto the neighbor, with no new touch-down. Treat
    // only a sudden jump that lands well inside another key as a new press;
    // gradual drift (a wobbly tap) never types.
    func recoverMergedFinger(for touchID: ObjectIdentifier, at point: CGPoint, previous: CGPoint) {
        guard directTouchRoutingEnabled, let tracked = trackedKeys[touchID],
              tracked.key.accessibilityLabel != "Delete",
              hypot(point.x - previous.x, point.y - previous.y) >= mergedFingerJump,
              let target = resolvedHit(at: point, with: nil) as? KeyboardButton,
              target !== tracked.key, target.insertsOnTouchDown,
              target.accessibilityLabel != "Space",
              target.bounds.insetBy(dx: 3, dy: 3).contains(target.convert(point, from: self))
        else { return }
        tracked.key.isHighlighted = false
        tracked.key.sendActions(for: .touchCancel)
        trackedKeys.removeValue(forKey: touchID)
        guard let key = beginDirectKey(at: point) else { return }
        trackedKeys[touchID] = TrackedTouch(touch: tracked.touch, key: key)
        mergedFingerRecoveryCount += 1
    }

    private func sweepStaleTouches() {
        for (id, tracked) in trackedKeys where tracked.isStale {
            trackedKeys.removeValue(forKey: id)
            tracked.key.isHighlighted = false
            tracked.key.sendActions(for: .touchCancel)
            staleTouchRecoveryCount += 1
        }
    }

    func cancelActiveTouches() {
        finishedTouches.removeAll()
        for tracked in trackedKeys.values {
            tracked.key.isHighlighted = false
            tracked.key.sendActions(for: .touchCancel)
        }
        trackedKeys.removeAll()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let position = touch.location(in: self)
            let tracing = onTouchDiagnostic != nil
            let started = tracing ? ProcessInfo.processInfo.systemUptime : 0
            let initiallyHit = tracing ? super.hitTest(position, with: event) : nil
            let key = beginTrackedDirectKey(for: ObjectIdentifier(touch),
                                            at: position, event: event, touch: touch)
            if let observer = onTouchDiagnostic {
                let finished = ProcessInfo.processInfo.systemUptime
                let deliveryMs = Int(max(0, min(10_000, (started - touch.timestamp) * 1_000)))
                let actionMs = Int(max(0, min(10_000, (finished - started) * 1_000)))
                let fromGap = key.map { initiallyHit !== $0 } ?? false
                observer(position, key?.accessibilityLabel, deliveryMs, actionMs,
                         fromGap)
            }
        }
    }

    // Drift onto a neighbor is still the same press; only a merged second
    // finger (a sudden jump) types again.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            recoverMergedFinger(for: ObjectIdentifier(touch), at: touch.location(in: self),
                                previous: touch.previousLocation(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            finishTrackedDirectKey(for: ObjectIdentifier(touch), at: touch.location(in: self))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            finishTrackedDirectKey(for: ObjectIdentifier(touch), at: touch.location(in: self),
                                   cancelled: true)
        }
    }
}

// Observes touches at the root without taking over UIKit's touch stream.
// In live keyboards it routes character touches early, and it also releases
// them: when the system edge gate swallows a touch, the key view may never
// see its end, and that used to latch the key so its next press was lost.
final class KeyboardRootTouchMonitor: UIGestureRecognizer {
    var onTouchBegan: ((UITouch) -> Void)?
    var onTouchEnded: ((UITouch, Bool) -> Void)?
    var onTouchMoved: ((UITouch) -> Void)?

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        for touch in touches { onTouchMoved?(touch) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        for touch in touches { onTouchBegan?(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        for touch in touches { onTouchEnded?(touch, false) }
        finishIfIdle(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        for touch in touches { onTouchEnded?(touch, true) }
        finishIfIdle(event)
    }

    // Stay in .possible while any finger is down so overlapping (rollover)
    // touches keep arriving here. Failing early stopped delivery of every
    // later finger until all were lifted. A recognizer can only move from
    // .possible to .failed, never directly to .cancelled.
    private func finishIfIdle(_ event: UIEvent) {
        let live = event.allTouches?.contains { touch in
            touch.phase != .ended && touch.phase != .cancelled
        } ?? false
        if !live { state = .failed }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

// UIKit asks this view for its own height when embedding it in the keyboard
// presentation. A generic controller view leaves UIKit to guess that height.
final class KeyboardInputView: UIInputView {
    // UIKit can hit-test a decorative surface instead of the transparent key
    // host after an extension-host layout transition. Prefer the live router
    // whenever the point is inside it, including with the canvas disabled.
    weak var keyRoutingView: KeyboardInteractionView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let keyRoutingView, !keyRoutingView.isHidden,
           keyRoutingView.isUserInteractionEnabled, keyRoutingView.alpha > 0.01 {
            let keyPoint = keyRoutingView.convert(point, from: self)
            if keyRoutingView.bounds.contains(keyPoint),
               let target = keyRoutingView.hitTest(keyPoint, with: event) {
                return target
            }
        }
        return super.hitTest(point, with: event)
    }
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
