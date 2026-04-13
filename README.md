# Meow

[English](README.md) | [简体中文](README.zh-CN.md)

A lightweight macOS launcher built with SwiftUI + AppKit.

## Features

- Global hotkey to open the launcher
- App search with launch-history ranking
- Built-in commands (Preferences / Quit)
- Menu bar controls and optional Dock icon
- Launch at login (subject to macOS signing rules)
- Runtime language switching (English / Simplified Chinese)
- Multiple color themes (default: Ginger Cat)

## Requirements

- macOS 14+
- Swift 5.9+

## Quick Start

```bash
# Build
swift build

# Run
.build/debug/Meow

# Build DMG
bash scripts/build-dmg.sh
```

To override bundle identifier:

```bash
APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh
```

## Usage

1. Launch Meow, then open the panel with the hotkey (default: `Cmd+Space`).
2. Type to search apps or commands.
3. Use `Up/Down` to select and press Enter to launch.
4. Open Preferences to adjust language, theme, hotkey, Dock, and menu bar options.

## Project Structure

- `Sources/MeowApp.swift`: app lifecycle and window management
- `Sources/LauncherViewModel.swift`: search and ranking logic
- `Sources/Views.swift`: launcher and preferences UI
- `Sources/Theme.swift`: theme palette system
- `Sources/Services.swift`: hotkey, status item, auto-launch, persistence
- `Sources/Resources/`: localization resources

## Notes

- There is currently no automated test target; validation is mainly manual.
- See [DEVELOPMENT.md](DEVELOPMENT.md) for development details.
