# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run debug binary
.build/debug/Meow

# Create distributable DMG
bash scripts/build-dmg.sh
```

Note: There is no automated test target. Use manual testing checklist in DEVELOPMENT.md.

## Architecture

### App Lifecycle & Windows
- `Sources/App/MeowApp.swift`: `@main` entry point (`MeowApp`) + `AppDelegate`
  - AppDelegate owns all service instances and coordinates settings changes
  - Three windows: `LauncherPanel` (search), `LauncherPanel` (translation), and `NSWindow` (preferences)
  - Global mouse monitors dismiss panels on outside click

### Models (Sources/Models/)
- `AppSettings.swift`: All user preferences persisted via `UserDefaults` (autoLaunch, dock icon, status item, launcher hotkey, translate hotkey, language, theme, clipboard history)
- `AppModels.swift`: `AppEntry` (launchable app), `CommandEntry` (built-in command), `SearchItem` enum unifying both
- `ClipboardModels.swift`: `ClipboardEntry`, `ClipboardContent` enum (text/image/file/unsupported)

### View Models
- `Sources/ViewModels/LauncherViewModel.swift`: `LauncherViewModel`
  - Substring search over apps + built-in commands + clipboard entries
  - Scoring: text match quality (exact > prefix > substring) + launch history recency/frequency
  - Built-in commands: "Preferences", "Quit Meow"

### Services (Sources/Services/)
- `SettingsStore.swift`: UserDefaults persistence for `AppSettings`
- `LaunchHistoryStore.swift`: Records app launches, provides recency/frequency scoring boost
- `ClipboardService.swift`: Monitors clipboard changes via Timer, stores last 50 entries with optional image caching
- `SystemServices.swift`: `DockService` (dock icon toggle), `StatusItemService` (menu bar), `AppDiscoveryService` (enumerates /Applications, /System/Applications, ~/Applications), `AutoLaunchService` (login item), `HotkeyService` (multi-hotkey via Carbon `RegisterEventHotKey` with signature `MEOW`)
- `TranslationService.swift`: Captures selected text via Accessibility API (`AXUIElementCopyAttributeValue`), falls back to simulating ⌘C to get text from clipboard

### Views (Sources/Views/)
- `LauncherView.swift`: Search bar + `LazyVStack` results list in a floating gradient panel, with clipboard history drawer
- `PreferencesView.swift`: Segmented General/Appearance sections, hotkey recorders, theme picker
- `TranslationView.swift`: Floating translation panel using `TranslationSession` (macOS 15+), auto-detects source language with `NLLanguageRecognizer`, switches between en/zh-Hans
- `Components/ItemComponents.swift`: Search result row rendering (app icon, clipboard preview, command chip)
- `Components/ActionMenu.swift`: Context menu for app/clipboard entries
- `Components/PreferenceRows.swift`: Reusable preference toggle rows, hotkey recorder row, language picker row, theme selector

### Theming
- `Sources/Theme.swift`: `ThemePalette` struct + `MeowTheme` enum with 4 presets (gingerCat, mistBlue, graphiteAmber, mossInk), each with light/dark variants. Palettes are pure functions of theme + color scheme. Applied via `ThemePalette` passed from `MeowTheme.palette(theme:scheme:)`.

## Common Tasks

**Add a new built-in command:**
1. Add a `CommandEntry` to the `commands` array in `LauncherViewModel` init
2. Handle the command ID in `LauncherViewModel.run(_:)`
3. Add localization keys in both `en.lproj/` and `zh-Hans.lproj/` `Localizable.strings`

**Add a preference:**
1. Add the property to `AppSettings` in `Sources/Models/AppSettings.swift` (include CodingKeys, init, decode, encode, default)
2. Add the UI row in `PreferencesView`
3. Handle the setting in `AppDelegate.apply(settings:)`

**Add localization:**
1. Add keys to `Sources/Resources/en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`
2. Add computed properties to the `L10n` enum in `Sources/Strings.swift`

## Key Design Decisions

- **Swift 6 concurrency**: Codebase targets Swift 6 strict checks. All services/view models are `@MainActor`. `HotkeyService` is `@unchecked Sendable` (Carbon APIs aren't Sendable). `LanguageManager.shared` is `nonisolated(unsafe)` (safe singleton pattern). `ApplicationServices` is imported `@preconcurrency`.
- **No test target**: Project intentionally omits automated tests; verify via manual checklist in DEVELOPMENT.md
- **No external dependencies**: Pure Apple frameworks (AppKit, SwiftUI, Carbon, ServiceManagement, Translation, NaturalLanguage)
- **Runtime language switching**: Not using `LocalizationCatalog` — swaps `Bundle` manually and increments a token to trigger SwiftUI rebuilds via `.id(lang.refreshToken)`
- **Carbon hotkeys**: Uses deprecated `RegisterEventHotKey` (not `CGEvent`) because it works reliably for global hotkey registration from a UIElement app
- **UIElement app**: `LSUIElement=true` in Info.plist — no dock icon by default; user toggles it in preferences
- **Translation on macOS 15+**: Uses the `Translation` framework (`.translationTask` modifier), which requires macOS 15. Minimum platform is `.macOS(.v15)`.
- **HotkeyService supports multiple hotkeys**: Launcher toggle (id=1) and translate (id=2), each with independent keyCode/modifiers/callback, stored in dictionaries
