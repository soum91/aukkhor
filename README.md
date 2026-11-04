# Aukkhor (অক্ষর)

Native iPhone keyboard with English, phonetic Bangla, and Bangla layouts, plus a separate Windows companion.

A native iOS custom keyboard and separate Windows companion. The app is a new project, not a Drift dependency.

## Whole keyboard glass

- Native `UIGlassEffect` now covers the entire keyboard and settings surface, including when **Keycaps: None** is selected. Keycap removal still removes every individual key fill, border, shadow and material.
- Clear and Frosted canvas styles, separate glass tint strength, and optional native touch response are available in theme settings. The keyboard panel also offers Clear/Frosted and Tint −/+ controls.
- Glass mode removes the opaque background beneath the canvas effect and avoids an extra system blur layer. Colors and local photo backgrounds can still be customized. Solid themes remain available with Glass off, and Reduce Transparency uses the solid theme background.
- The native canvas view and key views persist during ordinary typing. Tests cover glass with no keycaps, both canvas styles, the settings panel, accessibility fallback and retained view identity. Visual evidence uses a patterned backdrop to inspect native transparency and edge treatment; what is visible behind a keyboard in another app remains subject to the iOS host compositor.

## Hosted keyboard padding and latency

- The extension now supplies a self-sizing `UIInputView` with an explicit fitting size, a transparent root and a rounded background surface. Keyboard content has no extra vertical inset. The native globe band remains owned by iOS.
- Candidate buttons are allocated once and reused. Lookup is coalesced on a background queue, with stale results rejected; dictionary normalization is indexed once. Text insertion is not deferred.
- Unchanged keyboard appearances reuse their existing view tree instead of rebuilding it twice during presentation. Typing options and the haptic generator are cached; ordinary keys use immediate highlight feedback instead of system-button fades.
- Tests now present the keyboard through an actual responder host in addition to standalone geometry checks, and check that rapid prediction changes preserve button identity and cannot repaint stale results. Physical iPhone confirmation is still needed for the reported host-panel padding.

## Compact height and typing stability

- Removed the extra full-height utility footer. The default typing area is 220 points without numbers and 269 with numbers, down from 289/339; iOS adds its own bottom controls.
- Shift, caps lock and automatic capitalization update the existing letter buttons. They no longer rebuild all glass effects or reload the background photo while typing.
- Status messages overlay the top strip instead of moving typing targets. Candidate updates use plain text controls, and app preview renders only when its revision changes.
- Simulator coverage includes number-row on/off, all handedness modes, both system-globe states, material identity across Shift and stable key positions when status messages appear.

## Keyboard layout and theme update

- Native-style QWERTY geometry with equal letter widths, staggered second row, Shift and Delete beside row three, wide Space and 123/emoji/Return. Language, one-hand and settings controls share a compact top strip. A globe is shown only when iOS requests an input switcher; the system bottom strip is not duplicated.
- Left/Full/Right layout menu. Tools sit in the unused strip opposite the typing hand; full-width mode can open the rail using ⚙.
- Every key uses one appearance renderer. No key backgrounds removes fill, glass, outline and shadow, including Space, tools and suggestions.
- Apple's UIGlassEffect on iOS 26+, blur fallback on iOS 16–18, and Reduce Transparency support. Custom colors for background, letters, actions, text and accent; opacity, radius, spacing, height and photo controls.
- The settings preview renders the actual keyboard controller. Keyboard-local ⚙ controls remain usable if a signer removes shared App Group access.
- Main app plus keyboard extension only. The Share extension remains excluded as requested. OTP handoff uses Shortcuts; Windows clipboard sync and direct TV pairing remain available.
- Unit tests exercise 320/390/430/844-point layouts and all three handedness modes. CI retains screenshot attachments in its layout test result bundle. Physical iPhone, TV and Windows testing is still required.

### Feature audit against the earlier Aukkhor chat

| Request | Implementation and limits |
| --- | --- |
| English, Bangla, phonetic | Implemented; phonetic dictionary remains a starter implementation |
| Native geometry, number row, emoji, one hand | Implemented; emoji catalog is a curated offline subset |
| Full Black, Liquid Glass, removable keycaps, theme customization | Implemented through one renderer and real keyboard preview |
| Built-in iOS Text Replacement | Uses `requestSupplementaryLexicon`; iOS chooses entries it exposes |
| Paste, Cut, Define, Speak, cursor movement | Implemented; clipboard requires Full Access and tools enabled |
| Siri and OTP to Windows | App Intents / Shortcuts and explicit clipboard actions; no automatic SMS reader |
| Windows pasteboard sync | Foreground app sync plus explicit keyboard send/get |
| iPhone typing for TV and Windows | Direct paired connections; auto prompt polling while iPhone app is foregrounded |
| Password/OTP AutoFill like iOS | Apple's SMS/Mail AutoFill UI is unavailable inside a third-party keyboard. OTP fields display Paste OTP (explicit clipboard read) and Next keyboard (to reach Apple's AutoFill); expanded tools include OTP. |
| Remove Share extension | Excluded from current app and publishing pipeline |

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
- The former Share extension is excluded from the current app; use the Shortcuts intent for code forwarding.
- A single opt-in 4–8 digit one-time code may be sent by user action or a user-configured Shortcuts automation. On a field marked `.oneTimeCode`, the keyboard offers Paste OTP, which extracts a unique 4–8 digit code from the clipboard **only after the user taps it**, and Next keyboard to reach native iOS AutoFill. Expanded keyboard tools also include OTP when a site does not mark its code field correctly. The app does **not** read SMS, Apple Mail, Gmail, or notifications on its own.

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
6. Copy code text and use the containing app or the Forward Code to Windows Shortcut.

## Limitations and security

- Apple does not give custom keyboards a background SMS/mail/notification reader or unlimited background execution. Mail and Gmail would need their own explicitly authorized account integration, subject to provider APIs and permissions, to support inbox-driven codes.
- A keyboard is substituted with the system keyboard in secure-entry fields and certain host apps. It cannot read the text in those fields. Windows code injection is **user-triggered** via hotkey, not silent filling of every website.
- The keyboard must be granted Full Access for network transport and direct pasteboard operations. Aukkhor does not transmit typed keystrokes, only explicit clipboard/code actions.
- A code from Aukkhor is not inserted into an arbitrary Windows app automatically. Place the cursor in the intended field and press **Ctrl + Alt + B**, or click **Copy code** in the companion. The Windows companion must be running in the signed-in session.
- Initial pairing sends the pairing code over a TLS connection pinned to the fingerprint verified by the user. Credentials are stored in the iOS shared Keychain and the Windows user's DPAPI-protected settings. A certificate mismatch always fails closed.
- Pairing is per computer; reset/re-pair if Windows regenerates its certificate. Never publish certificates with their private keys, tokens, or signing material.
- Current signed iOS installations must preserve the App Group and shared Keychain entitlements across the host app and keyboard extension. A signer that strips either capability breaks shared pairing; no unsupported entitlement bypass is included.
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
5. The native Android TV keyboard includes English, phonetic Bangla and direct Bangla with a
   consonant/vowel selector. Navigate using the D-pad and press OK to type. Hold OK on ⌫ to
   erase repeatedly. Use 123 for symbols, the optional number-row switch on the setup screen,
   and an Enter key that follows the focused app's Search/Go/Next action.

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

## iOS installation

Current releases contain one unsigned IPA with the main app and keyboard extension. The Share extension and standalone installation probes are excluded as requested.

Sign the host app and embedded `AukkhorKeyboard.appex` with a common signing identity and valid profiles. Keep the App Group and shared Keychain entitlements consistent to share host theme preferences, photos and Windows pairing with the keyboard. If a signer removes App Group access, keyboard-local settings under ⚙ persist independently; photo sharing and host-to-keyboard preference sharing require the shared container. Pairing in the main app remains separate from keyboard-local preferences.

The build audits the keyboard-service identifier, display names, iPhoneOS metadata, arm64 binaries and absence of the Share extension. Simulator tests check actual row geometry, Space width, glass views and background-free keycaps. UI tests enable the installed extension through iOS Settings, type across its process boundary, and capture the full screen on first presentation, after an app switch and after reopening. Physical iPhone behavior, signing and TV/Windows connections still need device testing.

**Background: iOS** is the default for System and glass themes. It leaves the native keyboard background visible, without a second rounded or tinted panel confined to the extension. **Background: Custom** retains the separate Clear/Frosted glass canvas, tint and photos; its edge can contrast with iOS's surrounding chrome. Keycap removal and key glass are independent of this setting. iOS owns the globe area and any margins outside the extension. A reported iOS 27 app-switching regression adds an external top strip without changing the extension's bounds; the extension cannot remove that system area. Neither a height slider nor a negative inset is a verified fix for that OS defect.

For an installation failure, retain the full error code and log from FlareStore or EmberSign. A signer must provision both app identifiers and sign the embedded keyboard, as well as the host.

## VaultBridge one-time-code handoff

Aukkhor can fill a short-lived SMS code from VaultBridge when the host field is marked as a one-time code. VaultBridge receives the code through its `vaultbridge://otp?code=...` URL handler and writes only that expiring code to the existing Aukkhor app-group container. Tap the OTP suggestion in Aukkhor to fill and consume it. The inbox expires after five minutes and is deleted after use.

The Aukkhor app, keyboard, and share extension do not receive VaultBridge's password Keychain group. Codes stay on-device and are not uploaded by this handoff. Both apps must be signed by the same Apple team with the Aukkhor app-group entitlement present in both provisioning profiles. Configure a Messages automation in Shortcuts to open `vaultbridge://otp?code=[Message]`; VaultBridge accepts one unambiguous 4–10 digit run from the message.
