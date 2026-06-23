# Development Guide

## Project Structure

```
├── Sources/
│   ├── App/
│   │   └── MeowApp.swift            # App entry, AppDelegate, window management
│   ├── Models/
│   │   ├── AppModels.swift          # AppEntry, CommandEntry
│   │   ├── AppSettings.swift        # AppSettings, AISettings, enums (theme, lang, dock/date icon)
│   │   ├── AuthenticatorModels.swift # TOTP accounts, OTPAuth parsing, JSON backup models
│   │   ├── ClipboardModels.swift    # ClipboardEntry, ClipboardContent, SearchItem
│   │   ├── HealthReminderModels.swift # Health reminder settings, state, records, commands
│   │   ├── KeystrokeModels.swift    # Keystroke visualizer settings and display models
│   │   └── SpeechModels.swift       # Speech settings, runtime state, history entries
│   ├── Services/
│   │   ├── SystemServices.swift     # DockService, StatusItemService, AppDiscoveryService, AutoLaunchService, HotkeyService
│   │   ├── SettingsStore.swift      # UserDefaults-based persistence
│   │   ├── ClipboardService.swift   # ClipboardStore, ClipboardImageCache
│   │   ├── TranslationService.swift # AX text capture + fallback copy
│   │   ├── AIChatService.swift      # OpenAI-compatible chat completions
│   │   ├── AIChatHistoryStore.swift  # File-based conversation persistence
│   │   ├── AuthenticatorService.swift # TOTP lifecycle, Keychain storage, import/export
│   │   ├── AuthenticatorSyncService.swift # Optional iCloud Keychain synchronization
│   │   ├── CalendarService.swift    # Lunisolar calendar, solar terms, holidays, EventKit
│   │   ├── HealthReminderService.swift # Work/break timer, daily records, break overlay
│   │   ├── KeyDisplayFormatter.swift # Keyboard-layout-aware key labels
│   │   ├── KeystrokeVisualizerService.swift # Global key event tap + overlay window
│   │   ├── SpeechRecognitionService.swift # Audio capture, offline ASR, paste workflow
│   │   ├── SpeechModelStore.swift   # Speech model download, SHA-256 verification, and switching
│   │   ├── SpeechHistoryStore.swift # Transcript index and WAV persistence
│   │   ├── SherpaOnnxRecognizer.swift # sherpa-onnx C API wrapper
│   │   └── LaunchHistoryStore.swift # Launch frequency/recency tracking
│   ├── ViewModels/
│   │   └── LauncherViewModel.swift  # Search, ranking, app dispatch, clipboard management
│   ├── Views/
│   │   ├── LauncherView.swift       # Main search panel
│   │   ├── TranslationView.swift    # Floating translation panel
│   │   ├── AIChatView.swift         # AI chat with history sidebar
│   │   ├── AuthenticatorPanelView.swift # Search and copy TOTP accounts
│   │   ├── AuthenticatorPreferencesView.swift # Import, export, sync, account management
│   │   ├── HealthBreakOverlayView.swift # Health reminder break panel
│   │   ├── KeystrokeOverlayLayout.swift # Overlay sizing
│   │   ├── KeystrokeOverlayView.swift # Keystroke overlay SwiftUI view
│   │   ├── SpeechOverlayView.swift  # Non-activating speech status panel
│   │   ├── SpeechPreferencesView.swift # Speech model, permission, and history settings
│   │   ├── PreferencesView.swift    # Tabbed settings window
│   │   └── Components/
│   │       ├── ActionMenu.swift     # Contextual action menu overlay
│   │       ├── CalendarView.swift   # Menu bar calendar popover
│   │       ├── ItemComponents.swift # App icon / clipboard thumbnail
│   │       └── PreferenceRows.swift # Toggle/hotkey/theme/language/AI settings rows
│   ├── Strings.swift                # L10n enum + LanguageManager
│   ├── Theme.swift                  # ThemePalette with 4 themes
│   └── Resources/
│       ├── en.lproj/                # English strings
│       ├── zh-Hans.lproj/           # Chinese strings
│       └── solar_terms.json         # Solar term dates
├── Tests/
│   └── AuthenticatorTests.swift     # TOTP, parsing, JSON, settings, and sync merge tests
├── Package.swift                    # Swift Package manifest (Swift 6, macOS 15+)
├── scripts/
│   ├── build-dmg.sh                 # Create distributable DMG
│   └── create-icon.sh               # Generate app icon
├── .github/workflows/
│   ├── build.yml                    # CI
│   ├── release.yml                  # Release automation
│   └── dependabot-auto-merge.yml    # Auto-merge dependencies
└── dist/Meow.app/Contents/
    └── Info.plist                   # Production entitlements
```

## Architecture

### App Entry & Lifecycle
- **MeowApp.swift** (`Sources/App/`): App entry and AppDelegate
  - Sets up AppKit windows (launcher, translation, AI chat, preferences)
  - Manages system services (hotkey, status item, clipboard monitoring)
  - Handles language switching, settings persistence, and window lifecycle
  - Windows use `NSPanel` (non-activating, floating) or regular `NSWindow`

### State Management
- **AppSettings.swift** (`Sources/Models/`):
  - `AppSettings`: Codable struct persisted in `UserDefaults` via `SettingsStore`
  - `AISettings`: API endpoint, key, model, system prompt, chat history toggle
  - `DateIconStyle` / `DockIconStyle` / `AppTheme` / `AppLanguage` enums

- **LauncherViewModel.swift** (`Sources/ViewModels/`):
  - Command/app matching with scoring (exact > prefix > word > contains)
  - App discovery via `AppDiscoveryService`
  - Launch history ranking (recency + frequency)
  - Clipboard history management
  - Closure-based callbacks for window actions

### UI Layer
- **Views** (`Sources/Views/`): Per-feature SwiftUI views
  - `LauncherView`: Main search panel (borderless NSPanel with blur)
  - `TranslationView`: Floating translation panel using `Translation` framework
  - `AIChatView`: Chat window with conversation sidebar, markdown rendering
  - `AuthenticatorPanelView`: Search, inspect, and copy current TOTP codes
  - `AuthenticatorPreferencesView`: Account import/export, deletion, and sync controls
  - `PreferencesView`: Tabbed settings window, including a dedicated Authenticator tab
  - `HealthBreakOverlayView`: Floating break reminder with countdown, progress, and break actions
  - `KeystrokeOverlayView`: Draggable global keystroke overlay rendered in a non-activating panel
  - `Components/`: Reusable pieces — `ActionMenu`, `CalendarView`, `ItemComponents`, `PreferenceRows`
  - All views reactive to language changes via `.id(lang.refreshToken)`

### Services
- **SystemServices.swift** (`Sources/Services/`):
  - `HotkeyService`: Carbon-based global hotkeys (toggle, translate, and speech press/release), `@unchecked Sendable`
  - `StatusItemService`: NSStatusItem with custom date icons, calendar popover, menu
  - `DockService` / `DockIconService`: Activation policy toggle, runtime icon rendering
  - `AppDiscoveryService`: Scans system app directories
  - `AutoLaunchService`: SMAppService-based login item

- **ClipboardService.swift**: 0.5s pasteboard polling, 50-entry history, image caching
- **TranslationService.swift**: AX API text capture + Cmd+C fallback
- **AIChatService.swift**: `Sendable` async OpenAPI-compatible client
- **AIChatHistoryStore.swift**: `@MainActor ObservableObject`, file-based persistence
- **AuthenticatorService.swift**: TOTP generation, Keychain-backed account storage, clipboard-history exclusion, and JSON import/export
- **AuthenticatorSyncService.swift**: Optional synchronizable Keychain storage, merge behavior, and deletion tombstones
- **HealthReminderService.swift**: Work/break timer, daily UserDefaults records, break overlay, light activity detection via system idle time
- **KeystrokeVisualizerService.swift**: Accessibility-gated global key event tap, overlay window, drag persistence
- **SpeechRecognitionService.swift**: AVAudioEngine capture, 16 kHz mono conversion, sherpa-onnx inference, history, and temporary pasteboard restoration
- **SpeechModelStore.swift**: downloads only `model.int8.onnx` and `tokens.txt`, then verifies SHA-256 before installation
- **KeyDisplayFormatter.swift**: Current keyboard layout label lookup with fixed special-key fallback
- **CalendarService.swift** / **CalendarEventService.swift**: Lunisolar calendar, EventKit integration
- **LaunchHistoryStore.swift**: UserDefaults-based history scoring

### Localization
- **Strings.swift**:
  - `LanguageManager`: Runtime bundle switching without app restart
  - `L10n`: Computed property accessors using active bundle
  - Falls back to English if key not found
  - Both `en.lproj` and `zh-Hans.lproj` maintained in parallel

## Building

### Debug Build
```bash
swift build
```

### Release Build
```bash
swift build -c release
```

### Build Editions
```bash
# Base edition: Meow, without offline speech recognition or speech synthesis
swift build -c release --product Meow

# Voice edition: Miao, with offline speech recognition and speech synthesis
MEOW_EDITION=voice swift build -c release --product Miao
```

### Automated Tests
```bash
swift test
```

### Create DMG Package
```bash
bash scripts/build-dmg.sh

# Voice edition DMG
MEOW_EDITION=voice bash scripts/build-dmg.sh
```

This will:
1. Generate icon from `logo.png` if needed
2. Build release binary
3. Create `.app` bundle with resources
4. Embed ONNX Runtime in `Contents/Frameworks` for the Miao voice edition
5. Create `.dmg` installer

### Speech Native Dependencies

The package vendors universal macOS binaries in `Vendor/`:

- sherpa-onnx 1.13.2 static xcframework
- ONNX Runtime 1.24.4 dynamic xcframework

Speech models are not committed. They are downloaded on demand from the
configured source and checked against these SHA-256 values before being
installed into the user's Application Support directory:

```text
model.int8.onnx c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51
tokens.txt       f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc
```

Release bundles include `THIRD_PARTY_NOTICES.md` and the complete pinned
license texts under `THIRD_PARTY_LICENSES/`, including ONNX Runtime dependency
notices and the FunASR Model Open Source License Agreement 1.1.

Installed speech models can be switched in Preferences -> Speech between the
default multilingual SenseVoice model and the English Parakeet model.

Notes:
- Minimum supported macOS version is 15.0 (`Package.swift` and generated `Info.plist`).
- If `logo.png` is missing and `AppIcon.icns` does not exist, icon generation will fail.

## Coding Guidelines

### File Naming
- Use PascalCase for files: `MeowApp.swift`, `LauncherView.swift`
- One main type per file (exception: small related types)

### Code Organization
```swift
// MARK: - Type Definition
struct MyType {
    // MARK: - Properties
    var property: String
    
    // MARK: - Initialization
    init() { }
    
    // MARK: - Public Methods
    func doSomething() { }
    
    // MARK: - Private Methods
    private func helper() { }
}
```

### SwiftUI Views
- Use `.id()` modifier when views depend on Observable objects
- Prefer computed properties for dynamic content
- Extract complex views into separate structs

### Performance
- Cache expensive computations in `@State` or `@StateObject`
- Use `onReceive` instead of polling
- Lazy evaluate commands/apps

## Localization

### Adding Strings
1. Add to `L10n` enum in `Strings.swift`:
```swift
static var myString: String {
  loc("my_key")
}
```

2. Add keys to both `.lproj` files:
```
"my_key" = "English text";
```

### Changing Language at Runtime
```swift
LanguageManager.shared.apply(.chinese)
```

The app will:
- Swap bundle to `zh-Hans.lproj`
- Notify all observers via `@Published refreshToken`
- Trigger view rebuilds via `.id()` modifiers

## Testing

Run the Swift Testing suite plus the manual checklist and build verification commands below.

### Manual Testing Checklist
- [ ] App launches with status item in menu bar
- [ ] Search works with fuzzy matching
- [ ] Launching an app from results works
- [ ] Clipboard history captures and displays text/images/files
- [ ] Translation panel captures selected text (with and without AX permission)
- [ ] AI chat sends messages, renders markdown, streams response
- [ ] AI chat history creates, renames, deletes conversations
- [ ] Preferences window opens/closes and every tab is functional
- [ ] Authenticator can be disabled/enabled and opened from the launcher without leaving the launcher visible
- [ ] Manual Base32 and `otpauth://` imports work; unsupported algorithms are rejected
- [ ] Imported secrets and copied TOTP codes do not remain in Meow clipboard history
- [ ] JSON import/export shows the plaintext-secret warning and handles duplicates
- [ ] Account deletion persists after sync is disabled and re-enabled
- [ ] Unsigned builds fall back to local Keychain storage with a clear sync capability error
- [ ] Speech model download, cancellation, checksum verification, and deletion work
- [ ] Hold/release speech hotkey records, recognizes, pastes, and restores the clipboard
- [ ] Speech handles denied microphone/Accessibility permissions and Esc cancellation
- [ ] Speech history playback, copy, delete, clear, retention, and folder opening work
- [ ] Language switching (EN/ZH) at runtime
- [ ] Hotkey recording and global trigger works
- [ ] Status bar menu items functional
- [ ] Calendar popover shows lunar/solar/events info
- [ ] Auto-launch preference works
- [ ] Dock icon style switching (default/calendar/flat)
- [ ] Date icon style switching (7 styles)
- [ ] Theme switching (4 themes)
- [ ] Health reminder start, pause, resume, break start, skip, and done actions work
- [ ] Health reminder daily progress and skipped count persist locally
- [ ] Health reminder activity detection pauses break countdown during keyboard/mouse activity
- [ ] Health reminder controls in the menu bar calendar panel mirror current timer state
- [ ] Keystroke visualizer permission denied/granted states work
- [ ] Keystroke visualizer overlay displays shortcuts/special keys/all keys correctly
- [ ] Keystroke visualizer drag, reset, opacity, duration, style, and history settings work
- [ ] Key labels follow non-US keyboard layouts where possible
- [ ] Action menu on clipboard entries (paste/copy/delete/ask AI)

### Build Verification
```bash
# Run automated tests
swift test

# Check compilation
swift build -v
MEOW_EDITION=voice swift build --product Miao

# Check release compilation
swift build -c release --product Meow
MEOW_EDITION=voice swift build -c release --product Miao

# Build DMG
bash scripts/build-dmg.sh
MEOW_EDITION=voice bash scripts/build-dmg.sh

# Verify app bundle
ls -la dist/Meow.app/Contents/
ls -la dist/Miao.app/Contents/
```

## Debugging

### Enable Logging
Add `print()` statements and run with:
```bash
swift build && .build/debug/Meow
```

### Check Resources
```bash
# Verify .lproj bundles
ls -la dist/Meow.app/Contents/Resources/
ls -la dist/Miao.app/Contents/Resources/

# Check Localizable.strings
strings dist/Meow.app/Contents/Resources/en.lproj/Localizable.strings
```

### View System Events
In Terminal, monitor app behavior:
```bash
log stream --predicate 'process == "Meow"'
log stream --predicate 'process == "Miao"'
```

## Common Tasks

### Add a New Command
1. Add command entry in `LauncherViewModel.commands`
2. Handle command ID in `LauncherViewModel.run(_:)`
3. Add localization keys in both `Localizable.strings` files

### Add a Menu Bar Item
1. Update `StatusItemService.setup()` in `SystemServices.swift`
2. Add menu item action closure in the setup block
3. Add localization keys in both `.lproj` files

### Change Preferences Layout
1. Edit `PreferencesView` in `Sources/Views/PreferencesView.swift`
2. Update `AppSettings` in `Sources/Models/AppSettings.swift`
3. Handle in `AppDelegate.apply(settings:)` if system interaction needed

## Resources

- [Swift Package Manager](https://swift.org/package-manager/)
- [SwiftUI Documentation](https://developer.apple.com/xcode/swiftui/)
- [AppKit Documentation](https://developer.apple.com/documentation/appkit)
- [localization Best Practices](https://developer.apple.com/localization/)

## Getting Help

- Check existing issues and discussions
- Review [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
- Open a new issue with detailed description
