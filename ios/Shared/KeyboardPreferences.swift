import Foundation
import UIKit

enum KeyboardPreset: String, CaseIterable, Identifiable {
    case system, midnight, fullBlack, liquidGlass, clearPrism, blossom, mint, sunset, highContrast, custom

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
    static var textReplacement: Bool {
        get { data.object(forKey: "keyboardTextReplacement") as? Bool ?? true }
        set { data.set(newValue, forKey: "keyboardTextReplacement") }
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
        // The host plate is used only when the user explicitly selects it.
        // Clear Prism retains the separate rounded material used in build 61.
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
    var usesPressLens = false
    var onHighlightChanged: ((Bool, KeyboardButton) -> Void)?
    // Finger contact often rolls just beyond a narrow key before lifting.
    // Keep that press valid while it remains near the original key.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -9).contains(point)
    }
    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            // Avoid changing opacity of the entire key/material subtree.
            let pressedAlpha: CGFloat = usesPressLens ? 0.75 : 0.55
            titleLabel?.alpha = isHighlighted ? pressedAlpha : 1
            imageView?.alpha = isHighlighted ? pressedAlpha : 1
            if usesPressLens {
                let magnification: CGFloat = isHighlighted ? 1.09 : 1
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
final class KeyboardPressLensView: UIView {
    private let specular = CAGradientLayer()
    private let rim = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
        specular.colors = [UIColor.white.withAlphaComponent(0.4).cgColor,
                           UIColor.white.withAlphaComponent(0.07).cgColor,
                           UIColor.white.withAlphaComponent(0.03).cgColor,
                           UIColor.systemCyan.withAlphaComponent(0.13).cgColor]
        specular.locations = [0, 0.24, 0.8, 1]
        specular.startPoint = CGPoint(x: 0, y: 0)
        specular.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(specular)
        rim.fillColor = UIColor.clear.cgColor
        rim.strokeColor = UIColor.white.withAlphaComponent(0.32).cgColor
        rim.lineWidth = 1
        specular.mask = rim
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(over keyRect: CGRect) {
        // The specular only appears during a press. It sits behind the touch
        // host, so it cannot block or defer any character insertion.
        frame = keyRect.insetBy(dx: -6, dy: -7)
        isHidden = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        specular.frame = bounds
        rim.frame = bounds
        rim.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                               cornerRadius: bounds.height / 2).cgPath
        CATransaction.commit()
    }
}

// Fill only the small gaps between keys, without growing or moving their caps.
// Prefer the closest enabled key; never route outside the keyboard's bounds.
final class KeyboardInteractionView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              bounds.contains(point) else { return nil }
        // UIKit already finds direct key hits. Only search nearby keys when
        // the finger actually lands in a gap, not for every touch event.
        let direct = super.hitTest(point, with: event)
        if let key = direct as? UIButton, key.isEnabled,
           key.bounds.contains(key.convert(point, from: self)) { return key }
        var nearest: UIButton?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        func visit(_ parent: UIView) {
            for child in parent.subviews where !child.isHidden && child.alpha > 0.01 && child.isUserInteractionEnabled {
                if child.clipsToBounds && !child.bounds.contains(child.convert(point, from: self)) { continue }
                if let key = child as? UIButton, key.isEnabled {
                    let frame = key.convert(key.bounds, to: self)
                    guard frame.width > 0, frame.height > 0 else { continue }
                    let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
                    let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
                    let distance = dx * dx + dy * dy
                    if dx <= 10 && dy <= 10 && distance < nearestDistance {
                        nearest = key
                        nearestDistance = distance
                    }
                } else { visit(child) }
            }
        }
        visit(self)
        return nearest ?? direct
    }
}

// UIKit asks this view for its own height when embedding it in the keyboard
// presentation. A generic controller view leaves UIKit to guess that height.
final class KeyboardInputView: UIInputView {
    var contentHeight: CGFloat = KeyboardPreferences.typingHeight {
        didSet {
            if abs(oldValue - contentHeight) > 0.5 {
                invalidateIntrinsicContentSize()
                setNeedsUpdateConstraints()
                setNeedsLayout()
                superview?.setNeedsLayout()
            }
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
