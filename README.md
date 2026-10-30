# Aukkhor (অক্ষর)

Native iPhone keyboard with English, phonetic Bangla, and Bangla layouts, plus a separate Windows companion.

A native iOS custom keyboard and separate Windows companion. The app is a new project, not a Drift dependency.

## Current implementation

- English QWERTY, direct Bangla character keys, and phonetic Bangla composition with basic consonant conjuncts.
- Themed keyboard UI with System, Midnight, Blossom, Mint, Sunset, High Contrast, and Custom themes; adjustable accent and key corners.
- Custom theme photos selected using the native iOS Photos picker. Images are resized and stored only in the shared app container, and are never uploaded to the companion.
- Customizable key haptics, clicks, optional number row, conservative autocorrect, text replacements from the available iOS supplementary lexicon, basic suggestions, auto capitals, double-space period, caps lock, and hold-Space cursor movement.
- Offline emoji categories and keyword search; a session-only clipboard history that is populated by explicit user actions.
- Experimental English gesture/glide decoding (off by default; not Gboard-grade accuracy).
- Selected-text Cut, explicit Paste, system dictionary Define, Speak selected/nearby text, and keyboard language switch.
- Clipboard push/pull over mutually authenticated, certificate-pinned HTTPS on a private local network. Keyboard operations are explicitly initiated, not an invisible background monitor.
- Siri / Shortcuts intents for sending clipboard text and forwarding a one-time code. Windows keeps the code briefly and offers Copy or **Ctrl+Alt+B** to type it in the focused app.
- A user-invoked **Send code to Windows** Share extension can accept selected text from apps that expose text sharing, including compatible Mail/Gmail/Message views.
- A single opt-in 4–8 digit one-time code may be sent by user action or a user-configured Shortcuts automation. The app does **not** read SMS, Apple Mail, Gmail, or notifications on its own.

## Build

- iPhone: on macOS with Xcode 16+ and XcodeGen, `cd ios && xcodegen generate`, then open `Aukkhor.xcodeproj`. Set a development Team with matching App Group / Keychain capabilities for both targets. The CI workflow creates an **unsigned** IPA for sideload signing.
- Windows: install .NET 10 SDK. `dotnet publish windows/Aukkhor.Windows/Aukkhor.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true`. The Windows CI workflow packages it as a ZIP.

## Pairing

1. Start Aukkhor Windows. Choose a trusted, private Wi-Fi/LAN adapter and start its server. It listens on TCP **45789** using a locally generated HTTPS certificate (no internet/cloud endpoint).
   If Windows Firewall asks, allow Aukkhor on **Private networks only**. If it never prompts and pairing times out, add an inbound TCP 45789 allow rule limited to the Private network profile.
2. On the iPhone, open Aukkhor, enter the displayed PC IPv4, six-digit code, and the **full SHA-256 certificate fingerprint**. These must match the Windows display. Tap Pair.
3. Enable Aukkhor in iOS Settings > General > Keyboard > Keyboards > Add New Keyboard. Allow **Full Access** only if you want the pasteboard or Windows features. The keyboard app itself explains this.
4. Tap the clipboard buttons in the keyboard to pull from Windows or send the iPhone clipboard. In the containing app, enable foreground clipboard sync if desired.
5. In Shortcuts, add the Aukkhor actions **Forward Code to Windows** or **Send Clipboard to Windows**. To forward codes found in a Message, configure a Messages personal automation and feed its text to the Forward Code action. iOS may require a foreground/confirmation step depending on the trigger and OS version.
6. In Mail, Gmail, or Messages, select the code text and use **Share → Send code to Windows** when that app offers text sharing. Review the last two digits, then confirm.

## Limitations and security

- Apple does not give custom keyboards a background SMS/mail/notification reader or unlimited background execution. Mail and Gmail would need their own explicitly authorized account integration, subject to provider APIs and permissions, to support inbox-driven codes.
- A keyboard is substituted with the system keyboard in secure-entry fields and certain host apps. It cannot read the text in those fields. Windows code injection is **user-triggered** via hotkey, not silent filling of every website.
- The keyboard must be granted Full Access for network transport and direct pasteboard operations. Aukkhor does not transmit typed keystrokes, only explicit clipboard/code actions.
- A code from Aukkhor is not inserted into an arbitrary Windows app automatically. Place the cursor in the intended field and press **Ctrl + Alt + B**, or click **Copy code** in the companion. The Windows companion must be running in the signed-in session.
- Initial pairing sends the pairing code over a TLS connection pinned to the fingerprint verified by the user. Credentials are stored in the iOS shared Keychain and the Windows user's DPAPI-protected settings. A certificate mismatch always fails closed.
- Pairing is per computer; reset/re-pair if Windows regenerates its certificate. Never publish certificates with their private keys, tokens, or signing material.
- Current signed iOS installations must preserve the App Group and shared Keychain entitlements across the host app and both extensions. A signer that strips either capability breaks shared pairing; no unsupported entitlement bypass is included.
- Native Bangla and phonetic Bangla input are first-pass layouts, not complete Avro/Probhat implementations. More dictionary/rule testing is needed with native speakers.
- Predictive suggestions currently use a small built-in lexicon, not Apple's private prediction engine. Gboard's cloud search, GIF lookup, translation, advanced glide model, and Apple's microphone dictation are not reproduced.

## Changelog

### 0.2.0 (pre-release source, not signed or device-tested)

- Compared high-value features from Gboard and Apple's native keyboard. Implemented seven theme presets, custom accent and key rounding, preview UI, haptic/sound switches, number row, word candidates, conservative autocorrection, supplementary iOS text replacements, caps lock, auto capitalization, double-space punctuation, cursor movement, searchable emoji, and in-memory clipboard history.
- Added an opt-in experimental English glide decoder. It requires actual swipe gesture usability tests before release.
- Added local photo background themes via the system Photos picker, with on-device resize and a per-key translucent backdrop.
- Expanded phonetic Bangla conjuncts and a small curated set of common-word overrides. Native-speaker accuracy validation remains outstanding.
- Renamed the project, extensions, signing identifiers, Windows companion, release assets, and app icon to the user-confirmed Aukkhor name.

### 0.1.0 (source preview)

- Introduced iPhone host app, keyboard extension, three language modes, dictionary/speech tools, Siri/Shortcuts actions, HTTPS-pinned Windows companion, and OTP handoff.
- Added a user-confirmed text Share extension for one-time code forwarding.
- Added macOS and Windows build workflows. No device build or physical iPhone/Windows pairing has been verified yet.

## Comparison references

- Gboard iPhone listing: https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242
- Apple keyboard and QuickPath: https://support.apple.com/guide/iphone/enter-text-with-the-onscreen-keyboard-iph3c50f96e/ios
- Apple custom keyboard limitations: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html


## Android TV keyboard and iPhone remote typing (0.3 preview)

The Aukkhor Android TV source is in `android-tv/` and builds with Gradle on GitHub Actions.
The **signed** APK is released by `soum91/embertv` using its existing permanent Android
signing identity, not a temporary CI debug key. EmberTV's `repo.json` includes the app.

1. Install **Aukkhor TV Keyboard** through EmberTV or from the signed APK in EmberTV GitHub Releases.
2. Open the Aukkhor TV app. Start its foreground receiver and enable/select Aukkhor from the TV's
   Input Method settings. Once selected, it supplies a D-pad-friendly keyboard.
3. On the TV screen, read the private LAN IPv4, six-digit pairing code and SHA-256 certificate
   fingerprint. On the iPhone, open Aukkhor → **Android TV keyboard and iPhone typing**,
   enter those values and pair.
4. Enable **Prompt automatically for TV text fields** on iPhone. **Keep the Aukkhor app foregrounded**.
   When the selected Aukkhor TV IME sees a normal focused editor, the iPhone app opens a native
   text-entry sheet automatically and brings up the iPhone's keyboard. Tap **Send to TV** to
   commit the entered text to the currently focused TV field.
5. The native Android TV keyboard includes English, first-pass phonetic Bangla and direct Bangla,
   D-pad controls, Backspace, Space, symbols and Done.

**Limits:** iOS will suspend ordinary LAN polling while Aukkhor is backgrounded; this is not an
unattended Apple-Watch-style notification while the app is closed. For reliable background wake
a separate push-notification service and an Apple push-capable signing identity would be required.
Password fields reject remote input. Only apps using standard Android input-method APIs are
supported. A VPN or TV/router AP isolation can prevent communication. 2.4 GHz and 5 GHz devices
can communicate when both are bridged onto the same non-isolated LAN.

## Windows remote text entry

In the Windows companion, enable **Allow paired iPhone to type in focused Windows text fields**.
In Aukkhor on iPhone, enable **Prompt automatically for focused Windows text fields**. While
Aukkhor is foregrounded, focused native Windows Edit/RichEdit controls can trigger an iPhone
typing sheet. Text is inserted on explicit Send using Unicode input events. Browser web inputs,
password fields and elevated windows are not automatically supported or bypassed.

## iOS installation: standard and compatibility builds

The normal IPA preserves the keyboard's shared App Group and Keychain requirements. If your
signer rejects those entitlements, use `Aukkhor-compat-unsigned.ipa` instead. It includes the
keyboard and Share extension but strips optional App Group and custom Keychain-sharing
entitlements. **Limitations of the compat variant:** shared settings, photo themes, Windows
pairing across the host app and keyboard extension may not function; TV pairing and remote
typing work in the main app using its private Keychain.

Both IPAs are **unsigned** and need re-signing. Re-sign the **host app and both embedded .appex
extensions** with compatible bundle IDs, valid provisioning profiles and a common signing
identity; a signer that signs only the host does not produce an installable keyboard app.
The CI audit confirms arm64 and an iPhoneOS minimum deployment target of iOS 16.0. The current
runner used Xcode 26.6 and iPhoneOS SDK 26.5, which by itself does not establish a device
incompatibility with iOS 27.

For exact failure diagnosis obtain the full installation error code / log from FlareStore or
EmberSign. Typical causes include missing profiles, invalid signing entitlements, app identifier
mismatches, and incorrectly signed embedded extensions. Do not assume an Xcode or hardware
problem from a generic 'Could not install' message.
