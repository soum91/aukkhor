import UIKit

// The full emoji set, in Unicode order, grouped the way iOS groups it.
@MainActor enum EmojiLibrary {
    struct Section {
        let title: String
        let symbol: String
        let glyphs: [String]
    }

    // Emoji newer than this iOS's font draws as empty boxes, so hide them.
    static var supportedVersion: Double {
        if #available(iOS 26.4, *) { return 17.0 }
        if #available(iOS 18.4, *) { return 16.0 }
        if #available(iOS 17.4, *) { return 15.1 }
        if #available(iOS 16.4, *) { return 15.0 }
        return 14.0
    }

    private static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.split(separator: EmojiData.separator).map(String.init)
    }

    static let sections: [Section] = {
        let hidden = Set(EmojiData.newer.filter { $0.version > supportedVersion }
            .flatMap { split($0.glyphs) })
        return EmojiData.groups.map { group in
            Section(title: group.title, symbol: group.symbol,
                    glyphs: split(group.glyphs).filter { !hidden.contains($0) })
        }
    }()

    static let toned: Set<String> = Set(EmojiData.groups.flatMap { split($0.toned) })

    private static let named: [(glyph: String, name: String)] = EmojiData.groups.flatMap { group in
        zip(split(group.glyphs), split(group.names)).map { (glyph: $0, name: $1) }
    }

    static func search(_ query: String, limit: Int = 40) -> [String] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return [] }
        let visible = Set(sections.flatMap(\.glyphs))
        // Names that start with the query first, then any word match.
        var starts: [String] = [], contains: [String] = []
        for entry in named where visible.contains(entry.glyph) {
            guard words.allSatisfy({ entry.name.contains($0) }) else { continue }
            if entry.name.hasPrefix(String(words[0])) { starts.append(entry.glyph) }
            else { contains.append(entry.glyph) }
            if starts.count >= limit { break }
        }
        return Array((starts + contains).prefix(limit))
    }

    // Skin tone 1...5 (light to dark). The modifier replaces the variation
    // selector after each person in the sequence, per Unicode.
    static func applying(tone: Int, to glyph: String) -> String {
        guard (1...5).contains(tone), toned.contains(glyph),
              let modifier = Unicode.Scalar(UInt32(0x1F3FA + tone)) else { return glyph }
        var scalars = String.UnicodeScalarView()
        var skipSelector = false
        for scalar in glyph.unicodeScalars {
            if skipSelector && scalar.value == 0xFE0F { skipSelector = false; continue }
            skipSelector = false
            scalars.append(scalar)
            if scalar.properties.isEmojiModifierBase {
                scalars.append(modifier)
                skipSelector = true
            }
        }
        return String(scalars)
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        label.font = .systemFont(ofSize: floor(bounds.height * 0.74))
    }
    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.14) : .clear }
    }
}

// iOS-style emoji keyboard: a horizontally scrolling grid of every emoji,
// a section title, category tabs that follow the scroll, Frequently Used,
// and skin tones on long-press.
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onInsert: ((String) -> Void)?
    var onSearch: (() -> Void)?

    private var sections: [EmojiLibrary.Section] = []
    private let titleLabel = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let categories = UIStackView()
    private var categoryButtons: [UIButton] = []
    private var tonePicker: UIView?
    private let foreground: UIColor
    private let accent: UIColor
    private var currentSection = -1

    init(abc: UIButton, delete: UIButton, foreground: UIColor, accent: UIColor) {
        self.foreground = foreground
        self.accent = accent
        super.init(frame: .zero)
        accessibilityIdentifier = "keyboard.emoji"
        let recents = KeyboardPreferences.emojiRecents
        sections = (recents.isEmpty ? [] : [EmojiLibrary.Section(title: "Frequently Used", symbol: "clock",
                                                                 glyphs: recents)]) + EmojiLibrary.sections

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = foreground.withAlphaComponent(0.6)
        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.tintColor = foreground.withAlphaComponent(0.7)
        search.accessibilityLabel = "Search emoji"
        search.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        search.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let header = UIStackView(arrangedSubviews: [titleLabel, search])
        header.axis = .horizontal
        header.spacing = 6

        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        grid.accessibilityIdentifier = "keyboard.emojiGrid"
        if #available(iOS 26.0, *) {
            grid.leftEdgeEffect.isHidden = true
            grid.rightEdgeEffect.isHidden = true
        }
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.35
        grid.addGestureRecognizer(hold)

        categories.axis = .horizontal
        categories.distribution = .fillEqually
        for (index, section) in sections.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: section.symbol), for: .normal)
            button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 15), forImageIn: .normal)
            button.tintColor = foreground.withAlphaComponent(0.55)
            button.accessibilityLabel = section.title
            button.addAction(UIAction { [weak self] _ in self?.jump(to: index) }, for: .touchUpInside)
            categoryButtons.append(button)
            categories.addArrangedSubview(button)
        }
        let bar = UIStackView(arrangedSubviews: [abc, categories, delete])
        bar.axis = .horizontal
        bar.spacing = 4
        abc.widthAnchor.constraint(equalToConstant: 46).isActive = true
        delete.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let column = UIStackView(arrangedSubviews: [header, grid, bar])
        column.axis = .vertical
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        grid.setContentHuggingPriority(.defaultLow, for: .vertical)
        grid.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 16),
            bar.heightAnchor.constraint(equalToConstant: 32)
        ])
        setSection(0)
    }
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fit whole rows of square-ish cells into the grid height, as iOS does.
        // Header 16 + bar 32 + two 2pt gaps; computed from our own bounds
        // because the grid has not been laid out yet on the first pass.
        let height = bounds.height - 16 - 32 - 4
        guard height > 20 else { return }
        let rows = max(3, min(6, Int(height / 38)))
        let side = floor(height / CGFloat(rows))
        let size = CGSize(width: max(side, (bounds.width / 8.5).rounded(.down)), height: side)
        if layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].glyphs.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        let glyph = displayed(at: indexPath)
        cell.label.text = glyph
        cell.accessibilityLabel = glyph
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        UIEdgeInsets(top: 0, left: section == 0 ? 0 : 10, bottom: 0, right: 0)
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        insert(displayed(at: indexPath))
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        dismissTonePicker()
        let probe = CGPoint(x: scrollView.contentOffset.x + 12, y: scrollView.bounds.midY)
        if let path = grid.indexPathForItem(at: probe)
            ?? grid.indexPathsForVisibleItems.min(by: { $0 < $1 }) {
            setSection(path.section)
        }
    }

    // Shows the user's remembered skin tone for that emoji.
    private func displayed(at indexPath: IndexPath) -> String {
        let glyph = sections[indexPath.section].glyphs[indexPath.item]
        guard let tone = KeyboardPreferences.emojiTones[glyph] else { return glyph }
        return EmojiLibrary.applying(tone: tone, to: glyph)
    }

    private func insert(_ glyph: String) {
        onInsert?(glyph)
        KeyboardPreferences.rememberEmoji(glyph)
    }

    private func setSection(_ index: Int) {
        guard index != currentSection, sections.indices.contains(index) else { return }
        currentSection = index
        titleLabel.text = sections[index].title.uppercased()
        for (i, button) in categoryButtons.enumerated() {
            button.tintColor = i == index ? foreground : foreground.withAlphaComponent(0.45)
        }
    }

    private func jump(to index: Int) {
        guard sections.indices.contains(index), !sections[index].glyphs.isEmpty else { return }
        dismissTonePicker()
        grid.layoutIfNeeded()
        if let frame = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: index))?.frame {
            let maxX = max(0, grid.contentSize.width - grid.bounds.width)
            grid.setContentOffset(CGPoint(x: min(maxX, max(0, frame.minX - (index == 0 ? 0 : 10))), y: 0),
                                  animated: false)
        }
        setSection(index)
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let path = grid.indexPathForItem(at: recognizer.location(in: grid)),
              let cell = grid.cellForItem(at: path) else { return }
        let base = sections[path.section].glyphs[path.item]
        guard EmojiLibrary.toned.contains(base) else { return }
        showTonePicker(for: base, over: cell.convert(cell.bounds, to: self))
    }

    private func showTonePicker(for base: String, over cellFrame: CGRect) {
        dismissTonePicker()
        let picker = UIStackView()
        picker.axis = .horizontal
        picker.distribution = .fillEqually
        picker.backgroundColor = UIColor.secondarySystemBackground
        picker.layer.cornerRadius = 10
        picker.layer.shadowColor = UIColor.black.cgColor
        picker.layer.shadowOpacity = 0.25
        picker.layer.shadowRadius = 6
        picker.accessibilityIdentifier = "keyboard.emojiTones"
        for tone in 0...5 {
            let glyph = tone == 0 ? base : EmojiLibrary.applying(tone: tone, to: base)
            let button = UIButton(type: .system)
            button.setTitle(glyph, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.accessibilityLabel = glyph
            button.addAction(UIAction { [weak self] _ in
                KeyboardPreferences.setEmojiTone(tone, for: base)
                self?.insert(glyph)
                self?.dismissTonePicker()
                self?.grid.reloadData()
            }, for: .touchUpInside)
            picker.addArrangedSubview(button)
        }
        let width = min(bounds.width - 8, 6 * 44)
        let x = min(max(4, cellFrame.midX - width / 2), bounds.width - width - 4)
        picker.frame = CGRect(x: x, y: max(0, cellFrame.minY - 50), width: width, height: 46)
        addSubview(picker)
        tonePicker = picker
    }

    private func dismissTonePicker() {
        tonePicker?.removeFromSuperview()
        tonePicker = nil
    }

    #if DEBUG
    var testingSectionTitles: [String] { sections.map(\.title) }
    func testingSelect(section: Int, item: Int) {
        collectionView(grid, didSelectItemAt: IndexPath(item: item, section: section))
    }
    #endif
}
