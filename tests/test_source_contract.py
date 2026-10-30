import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class SourceContract(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text(encoding="utf-8")

    def test_same_secure_transport_and_port(self):
        ios = self.read("ios/Shared/AukkhorLink.swift")
        win = self.read("windows/Aukkhor.Windows/AukkhorService.cs")
        self.assertIn('"https://\\(host):45789"', ios)
        self.assertIn("const int Port = 45789", win)
        self.assertIn("UseHttps(certificate)", win)
        self.assertIn("SecCertificateCopyData(cert)", ios)

    def test_route_agreement(self):
        ios = self.read("ios/Shared/AukkhorLink.swift")
        win = self.read("windows/Aukkhor.Windows/AukkhorService.cs")
        for route in ("pair", "challenge", "reconnect", "clipboard", "code"):
            self.assertIn(f'"{route}"', ios)
            self.assertIn(f'"/{route}"', win)

    def test_security_guards(self):
        ios = self.read("ios/Shared/AukkhorLink.swift")
        win = self.read("windows/Aukkhor.Windows/AukkhorService.cs")
        self.assertIn("CryptographicOperations.FixedTimeEquals", win)
        self.assertIn("HMAC<SHA256>", ios)
        self.assertIn("HMACSHA256.HashData", win)
        self.assertIn("kSecAttrAccessGroup", ios)
        self.assertIn("ProtectedData.Protect", win)
        self.assertIn("TakeCode(consume: true)", self.read("windows/Aukkhor.Windows/MainForm.cs"))

    def test_extension_and_entitlements(self):
        project = self.read("ios/project.yml")
        self.assertIn("com.apple.keyboard-service", project)
        self.assertIn("RequestsOpenAccess: true", project)
        for path in ["ios/App/Aukkhor.entitlements", "ios/Keyboard/AukkhorKeyboard.entitlements", "ios/Share/AukkhorShare.entitlements"]:
            contents = self.read(path)
            self.assertIn("group.dev.soum91.aukkhor", contents)
            self.assertIn("dev.soum91.aukkhor.shared", contents)
        self.assertIn("com.apple.share-services", project)

    def test_foreground_and_explicit_code(self):
        app = self.read("ios/App/AukkhorApp.swift")
        intents = self.read("ios/App/AukkhorIntents.swift")
        self.assertIn("scenePhase == .active", app)
        self.assertIn("@Parameter(title:", intents)
        self.assertIn("CodeExtractor.extract(text)", self.read("ios/Shared/AukkhorLink.swift"))

    def test_keyboard_feature_preferences(self):
        source = self.read("ios/Shared/KeyboardPreferences.swift")
        for name in ("midnight", "blossom", "mint", "sunset", "highContrast", "custom",
                     "haptics", "keySounds", "numberRow", "autocorrect", "doubleSpacePeriod",
                     "experimentalGlide"):
            self.assertIn(name, source)
        self.assertIn("containerURL(forSecurityApplicationGroupIdentifier:", source)
        self.assertIn("keyboard-background.jpg", source)
        app = self.read("ios/App/AukkhorApp.swift")
        self.assertIn("PhotosPicker", app)
        self.assertIn("removeBackgroundImage()", app)

    def test_keyboard_high_value_features(self):
        keyboard = self.read("ios/Keyboard/KeyboardViewController.swift")
        for symbol in ("requestSupplementaryLexicon", "EmojiCatalog.search", "UIInputViewAudioFeedback",
                       "adjustTextPosition(byCharacterOffset:", "glideCandidate", "recordClip",
                       "keyboardDoubleSpace", "KeyboardSuggestions.complete"):
            if symbol == "keyboardDoubleSpace":
                self.assertIn("KeyboardPreferences.doubleSpacePeriod", keyboard)
            else:
                self.assertIn(symbol, keyboard)
        self.assertIn("Session-only", keyboard)

    def test_no_hidden_clipboard_poll_in_extension(self):
        keyboard = self.read("ios/Keyboard/KeyboardViewController.swift")
        self.assertNotIn("Timer.scheduledTimer", keyboard)
        self.assertNotIn("UIPasteboard.changedNotification", keyboard)
        self.assertNotIn("general.changeCount", keyboard)


if __name__ == "__main__":
    unittest.main()

