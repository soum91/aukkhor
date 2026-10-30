import AppIntents
import UIKit

struct SendAukkhorClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Clipboard to Windows"
    static var description = IntentDescription("Send the current iPhone text clipboard to your paired PC.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let text = UIPasteboard.general.string else { throw AukkhorError.noClipboard }
        try await AukkhorLink.shared.sendClipboard(text)
        return .result(dialog: "Clipboard sent to Windows.")
    }
}

struct ForwardAukkhorCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Forward Code to Windows"
    static var description = IntentDescription("Forward a 4–8 digit code supplied by you or a Shortcuts automation.")

    @Parameter(title: "Message text or one-time code") var messageText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Forward \(\.$messageText) to Windows")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let code = try await AukkhorLink.shared.sendCode(from: messageText)
        return .result(dialog: "Code ending \(code.suffix(2)) sent to Windows.")
    }
}

struct AukkhorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(intent: SendAukkhorClipboardIntent(),
                        phrases: ["Send clipboard with \(.applicationName)"],
                        shortTitle: "Send clipboard", systemImageName: "doc.on.clipboard"),
            AppShortcut(intent: ForwardAukkhorCodeIntent(),
                        phrases: ["Forward \(\.$messageText) with \(.applicationName)"],
                        shortTitle: "Forward code", systemImageName: "number.square")
        ]
    }
}

