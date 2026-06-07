# Meow

[English](README.md) | [简体中文](README.zh-CN.md)

A lightweight macOS launcher with gadgets, built with SwiftUI + AppKit.

## Features

- Global hotkey (`Opt+Space`) to open the launcher
- App search with launch-history ranking
- Clipboard history with paste, copy, delete, and clear actions
- Built-in commands (Preferences / Ask AI / Quit)
- OpenAI-compatible AI chat assistant with local chat history
- Ask AI from clipboard entries
- Translation panel for selected text (requires Accessibility permission)
- Offline speech recognition with a hold-to-talk shortcut, automatic paste, and local WAV history
- Keystroke visualizer with draggable overlay, display modes, duration, opacity, and history count
- Health reminder with work/break timer, break overlay, daily goal, and light activity detection
- Menu bar calendar with Chinese lunisolar dates, solar terms, and Calendar.app events
- 7 menu bar date icon styles (paw print, outlined day, rounded outline, day only, month+day, weekday+day, lunar date)
- 3 Dock icon styles (default, calendar, flat)
- Action menu on items (open, reveal in Finder, copy, paste, ask AI, delete)
- 4 color themes: Ginger Cat, Mist Blue, Graphite Amber, Moss Ink
- Runtime language switching (English / Simplified Chinese)
- Launch at login (subject to macOS signing rules)

## Requirements

- macOS 15+
- Swift 6.0+

## Quick Start

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run
.build/debug/Meow

# Package DMG
bash scripts/build-dmg.sh
```

The DMG build script regenerates `AppIcon.icns` when `logo.png` is newer than the current generated icon.

To override bundle identifier:

```bash
APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh
```

## Usage

1. Launch Meow, then open the panel with the hotkey (default: `Opt+Space`).
2. Type to search apps or commands.
3. Use `Up/Down` to select and press Enter to launch or run a command.
4. Use the action menu on clipboard entries to paste, copy, delete, reveal files, or ask AI.
5. Open Preferences to adjust language, theme, hotkeys, Dock, menu bar, clipboard, health reminders, keyboard overlay, and AI settings.

## Offline Speech Recognition

Configure speech recognition from Preferences -> Speech.

- Enable the feature, then hold `Option+R` for up to 30 seconds and release to recognize and paste
- Uses sherpa-onnx and on-device speech models, including multilingual SenseVoice Small int8 and English Parakeet int8
- Downloads the approximately 230 MB model only after confirmation in Preferences
- Supports Chinese, English, Japanese, Korean, and Cantonese
- Saves successful transcripts and WAV recordings locally for 30 days by default
- Requires Microphone permission; automatic paste also requires Accessibility permission

Speech history and models are stored under:

```text
~/Library/Application Support/Meow/ASRHistory/
~/Library/Application Support/Meow/Models/ASR/
```

## Health Reminder

Meow can alternate focused work sessions with short breaks. Configure it from Preferences -> Health.

- Starts a work timer and prompts you when it is time to rest
- Shows controls in the menu bar calendar panel plus a floating break overlay
- Tracks today's completed and skipped breaks locally
- Can pause the break countdown when keyboard or mouse activity is detected
- Supports gentle and strict break window modes

## Keystroke Visualizer

Meow can show global keystrokes in a draggable overlay. Configure it from Preferences -> Keyboard.

- Requires Accessibility permission for global key monitoring
- Supports shortcut-only, shortcuts + special keys, and all-keys display modes
- Supports compact/prominent styles, preset or custom overlay position, opacity, display time, and 1-3 item history
- Key labels follow the current macOS keyboard layout when possible

## AI Assistant

Meow includes an OpenAI-compatible chat assistant. Configure it from Preferences -> AI with:

- Endpoint, for example `https://api.openai.com/v1/chat/completions`
- API key
- Model name, either typed manually or fetched from the provider's `/models` endpoint

Chat history is stored locally under:

```text
~/Library/Application Support/Meow/AIChats/
```

API keys remain in Meow's local settings storage. Chat history can be disabled, cleared, or opened from the AI settings screen.

## Project Structure

- `Sources/App/MeowApp.swift`: app lifecycle and window management
- `Sources/ViewModels/LauncherViewModel.swift`: search and ranking logic
- `Sources/Views/`: launcher, AI chat, preferences, translation, and UI components
- `Sources/Theme.swift`: theme palette system
- `Sources/Services/`: hotkey, status item, auto-launch, clipboard, translation, speech recognition, AI chat, and persistence
- `Sources/Models/`: app, clipboard, and settings models
- `Sources/Resources/`: localization resources

## Notes

- There is currently no automated test target; validation is mainly manual.
- For AI changes, manually check configured and unconfigured states, model fetch/manual entry, Enter send, Shift+Enter newline, chat history, and opening the history folder.
- For health reminder changes, manually check timer start/pause/resume, break start/skip/done, daily goal progress, activity-paused countdown, and menu bar calendar controls.
- For keyboard overlay changes, manually check Accessibility permission denied/granted states, hotkey conflict behavior, dragging/resetting the overlay, and non-US keyboard layouts.
- See [DEVELOPMENT.md](DEVELOPMENT.md) for development details.
