import UIKit
import UniformTypeIdentifiers

/// User-invoked text Share extension, never a background inbox reader.
final class ShareViewController: UIViewController {
    private var suppliedText = ""
    private let label = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
        let heading = UILabel()
        heading.text = "Aukkhor · Forward code"
        heading.font = .boldSystemFont(ofSize: 22)
        stack.addArrangedSubview(heading)
        label.text = "Checking shared text…"
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
        button.setTitle("Send code to my Windows PC", for: .normal)
        button.configuration = .filled()
        button.isEnabled = false
        button.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        stack.addArrangedSubview(cancel)
        readSharedText()
    }

    private func readSharedText() {
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            if let text = item.attributedContentText?.string, CodeExtractor.extract(text) != nil {
                use(text); return
            }
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] content, _ in
                    let text = (content as? String) ?? (content as? NSAttributedString)?.string ?? ""
                    DispatchQueue.main.async { self?.use(text) }
                }
                return
            }
        }
        label.text = "No shared message text was provided. Select the code as text and share again."
    }

    private func use(_ text: String) {
        guard let code = CodeExtractor.extract(text) else {
            label.text = "No single 4–8 digit code detected in the selected text."
            return
        }
        suppliedText = text
        label.text = "Code ending \(code.suffix(2)) is ready. Send it to the paired PC?"
        button.isEnabled = true
    }

    private func send() {
        button.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await AukkhorLink.shared.sendCode(from: suppliedText)
                await MainActor.run { self.finish() }
            } catch {
                await MainActor.run {
                    self.label.text = error.localizedDescription
                    self.button.isEnabled = true
                }
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

