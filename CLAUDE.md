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

# Build verification
swift build -v
swift build -c release -v
```

Note: There is no automated test target. Use manual testing checklist in DEVELOPMENT.md.

## Architecture

### App Lifecycle & Windows
- [MeowApp.swift](Sources/MeowApp.swift): `@main` entry point + `AppDelegate`
  - Creates two windows: borderless `LauncherPanel` (NSPanel) and `NSWindow` for Preferences
  - Owns all service instances and coordinates settings changes
  - Sets up global mouse monitors for outside-click dismissal

### State & Models
- [Models.swift](Sources/Models.swift): `AppSettings`, `AppEntry`, `CommandEntry`, `SearchItem`
  - `AppSettings`: persisted via `UserDefaults` (autoLaunch, showDockIcon, showStatusItem, hotkey, language)
  - `SearchItem`: enum with `.app(AppEntry)` and `.command(CommandEntry)` cases

### Search & Launch Logic
- [LauncherViewModel.swift](Sources/LauncherViewModel.swift): `LauncherViewModel`
  - Substring search over apps + built-in commands
  - Scoring: text match quality (exact > prefix > substring) + launch history recency/frequency
  - Built-in commands: "Preferences", "Quit Meow"

### Services (all in [Services.swift](Sources/Services.swift))
- `SettingsStore`: UserDefaults persistence
- `LaunchHistoryStore`: records launches, provides scoring boost
- `DockService`: `TransformProcessType` to toggle dock icon visibility
- `StatusItemService`: `NSStatusItem` menu bar controls
- `AppDiscoveryService`: enumerates `/Applications`, `/System/Applications`, `~/Applications`
- `AutoLaunchService`: `SMAppService.mainApp` register/unregister
- `HotkeyService`: Carbon `RegisterEventHotKey` with `EventHotKeyID` signature `MEOW`

### Localization
- [Strings.swift](Sources/Strings.swift): `LanguageManager` + `L10n` enum
  - `LanguageManager.shared.apply(language)` swaps the active `Bundle`
  - SwiftUI views rebuild via `.id(lang.refreshToken)` modifier
  - Localization files: `Sources/Resources/en.lproj/Localizable.strings`, `zh-Hans.lproj/Localizable.strings`

### UI
- [Views.swift](Sources/Views.swift):
  - `LauncherView`: search bar + `LazyVStack` results list, floating gradient panel
  - `PreferencesView`: segmented General/Appearance sections with animated toggles
  - `PreferenceHotkeyRecorderRow`: local `NSEvent` monitor for key recording

## Key Design Decisions

- **No test target**: project intentionally omits automated tests; verify via manual checklist in DEVELOPMENT.md
- **No external dependencies**: pure Apple frameworks (AppKit, SwiftUI, Carbon, ServiceManagement)
- **Runtime language switching**: not using `LocalizationCatalog` — instead swaps `Bundle` manually and increments a token to trigger SwiftUI rebuilds
- **Carbon hotkeys**: uses deprecated Carbon API (`RegisterEventHotKey`) rather than modern `CGEvent` because it works reliably across macOS versions for global hotkey registration from a menu bar app
- **UIElement app**: `LSUIElement=true` in Info.plist means no dock icon by default; user toggles visibility via preferences
