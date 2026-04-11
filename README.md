# Meow - Native macOS Launcher

A native SwiftUI + AppKit launcher for macOS, with global hotkeys, menu bar integration, runtime language switching, and quick app/command search.

## Features

- Fast app and command search with ranking
- English and Simplified Chinese with in-app switching
- Custom global hotkey recording
- Launch history aware ranking
- Status bar menu controls
- Optional launch at login
- Optional Dock icon visibility

## Requirements

- macOS 14.0 or later
- Swift 5.9+
- Xcode Command Line Tools

## Installation

### Download DMG

Visit the [Releases](https://github.com/lurenyang/meow/releases) page and download the latest `Meow_*.dmg` file.

### Build from source

```bash
# Debug build
swift build

# Run debug binary
.build/debug/Meow

# Build release app + DMG
bash scripts/build-dmg.sh
```

Build artifacts:
- App bundle: `dist/Meow.app`
- DMG: `dist/Meow_<version>_<arch>.dmg` (for example: `arm64` or `x86_64`)
- DMG contents: `Meow.app` + `Applications` shortcut for drag-and-drop install

## Usage

1. Launch `Meow.app`
2. Press the configured hotkey (default: Cmd+Space)
3. Type to search apps and built-in commands
4. Press Enter to activate selection

Preferences are available from:
- Menu bar icon -> `Preferences...`
- App shortcut `Cmd+,`
- Built-in search command `Meow Preferences`

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and contributor workflow.

### Quick start

```bash
# Compile
swift build

# Run
.build/debug/Meow

# Release compile
swift build -c release

# Build distributable package
bash scripts/build-dmg.sh
```

Note: There is currently no automated test target in this package. Use the manual checklist in [DEVELOPMENT.md](DEVELOPMENT.md#testing).

## Project structure

- `Sources/`
  - `MeowApp.swift`: app entry, app delegate, windows lifecycle
  - `LauncherViewModel.swift`: search/filter/ranking and activation
  - `Views.swift`: launcher and preferences UI
  - `Services.swift`: hotkey, auto-launch, status bar, discovery, persistence helpers
  - `Models.swift`: settings and search item models
  - `Strings.swift`: runtime localization manager and string accessors
  - `Resources/`: localization resources
    - `en.lproj/Localizable.strings`
    - `zh-Hans.lproj/Localizable.strings`
- `scripts/build-dmg.sh`: release app + DMG packaging
- `scripts/create-icon.sh`: icon generation helper
- `Package.swift`: SwiftPM manifest

## Architecture overview

Main components:
- Launcher panel (borderless `NSPanel`)
- Preferences window (`NSWindow` with SwiftUI)
- Status bar menu (`NSStatusItem`)
- Global hotkey service (Carbon)
- App discovery service (`/Applications`, `/System/Applications`, `~/Applications`)
- Language manager with runtime resource bundle switching

Search behavior:
- Commands and apps are matched with substring search
- Score combines text match quality and launch history recency/frequency
- Results are sorted by score, then localized name

## Localization

Supported languages:
- English
- Simplified Chinese (`zh-Hans`)

To add a new language, follow [DEVELOPMENT.md](DEVELOPMENT.md#localization).

## Configuration

Settings are persisted in `UserDefaults` under app-specific keys.

Saved preferences include:
- launch at login
- menu bar visibility
- Dock icon visibility
- global hotkey keycode/modifiers
- language mode

## Troubleshooting

### Hotkey does not trigger
- Check current hotkey in Preferences
- Ensure no other app is using the same shortcut

### Language did not update
- Change language again in Preferences to trigger refresh
- Reopen launcher/preferences windows

### Packaging issues
- Ensure `AppIcon.icns` exists, or provide `logo.png` at repo root for icon generation
- Re-run `bash scripts/build-dmg.sh`

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

See [LICENSE.md](LICENSE.md).
