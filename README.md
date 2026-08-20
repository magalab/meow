# Meow

[English](README.md) | [简体中文](README.zh-CN.md)

A lightweight macOS launcher with gadgets, built with SwiftUI + AppKit.

## Features

- Global hotkey (`Opt+Space`) to open the launcher
- App search with launch-history ranking
- Clipboard history with paste, copy, delete, and clear actions
- Native region, window, and display screenshots with frozen multi-display
  selection, full-resolution local history, and configurable copy/save output
- Native screen recording for displays, regions, windows, applications, system audio,
  cameras, and connected mobile capture devices
- Optional desktop whiteboard with shapes, arrows, freehand drawing, text, images,
  local autosave, and PNG/SVG/Excalidraw interchange
- Optional system monitor with a separate menu bar item, compact metric cards, IPv4
  address display, and configurable sampling/history settings
- S3-compatible file uploads with AWS S3, Cloudflare R2, MinIO, custom endpoints,
  upload shortcuts, clipboard commands, and menu bar drag-and-drop
- Built-in commands (Preferences / Ask AI / Quit)
- OpenAI-compatible AI chat assistant with local chat history
- Ask AI from clipboard entries
- Translation panel for selected text (requires Accessibility permission)
- System text service and `Option+X` action panel for translating, asking AI, or reading selected text aloud in Miao
- Offline speech recognition with a hold-to-talk shortcut, automatic paste, and local WAV history
- Offline Chinese and English speech synthesis with local playback, WAV export, and clipboard read-aloud actions
- Keystroke visualizer with draggable overlay, display modes, duration, opacity, and history count
- Health reminder with work/break timer, break overlay, daily goal, and light activity detection
- Menu bar calendar with Chinese lunisolar dates, solar terms, and Calendar.app events
- TOTP authenticator with Keychain storage, `otpauth://` and JSON import, JSON backup, search, and one-click copy
- Optional iCloud Keychain sync for authenticator accounts when using a properly signed build
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

Meow has two build editions:

```bash
# Base edition: Meow, without offline speech recognition or speech synthesis
swift build -c release --product Meow
bash scripts/build-dmg.sh

# Voice edition: Miao, with offline speech recognition and speech synthesis
MEOW_EDITION=voice swift build -c release --product Miao
MEOW_EDITION=voice bash scripts/build-dmg.sh
```

The default bundle identifiers are `tech.lury.meow` for Meow and `tech.lury.miao` for Miao.

To override bundle identifier:

```bash
APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh
```

## Usage

1. Launch Meow, then open the panel with the hotkey (default: `Opt+Space`).
2. Type to search apps or commands.
3. Use `Up/Down` to select and press Enter to launch or run a command.
4. Use the action menu on clipboard entries to paste, copy, delete, reveal files, or ask AI.
5. Open Preferences to adjust language, theme, hotkeys, Dock, menu bar, clipboard, whiteboard, file hosting, authenticator, health reminders, keyboard overlay, and AI settings.

## Selected Text Actions

Select text in an app that supports macOS Services, then choose **Services -> Process with Meow** (or Miao) from its context or application menu. Meow opens one action panel for translation and Ask AI; Miao also shows Read Aloud when offline text-to-speech is enabled.

The default global shortcut is `Option+X` and can be changed under Preferences -> General -> Shortcuts. The Services entry receives selected text directly and does not require Accessibility permission. The global shortcut uses Meow's selection capture fallback and therefore does require Accessibility permission. macOS normally places the entry in the Services submenu; Meow cannot force it into the top level of every app's context menu.

Launch Services discovers this integration from the packaged application bundle. Run the packaged `.app` when testing the context-menu entry; invoking `.build/debug/Meow` directly is insufficient.

## Screenshots

Configure screenshots from Preferences -> Screenshot.

- Capture a region, a window, or an entire display from global shortcuts or launcher commands
- Select from frozen display images so moving content does not change during selection
- Copy, save, or copy and save using PNG or JPEG
- Choose a default quick-capture mode and independent quick, edit, window, and display shortcuts
- Store full-resolution captures under `~/Library/Application Support/Meow/Captures/`
- Add captures to Meow clipboard history without applying the clipboard image size limit
- Save to `~/Pictures/Meow/` by default or choose another directory
- Configure history retention by capture count, age, and local storage size
- Use the draggable post-capture action bar to copy, save, edit, pin, OCR, translate, or ask AI;
  choose 5, 10, or 20 seconds, or never auto-hide, with the timer paused while hovered
- Crop, resize, annotate, highlight, number, and destructively redact captures in the editor
- Pin clipboard images in resizable always-on-top windows
- Recognize English and Simplified Chinese text locally with Vision, copy it, or send it to the
  translation panel with a source-image preview. Automatic OCR history indexing is off by default;
  enabling it stores recognized text locally for search and may include sensitive content
- Scan QR codes and confirm `otpauth://` imports before storing secrets in Keychain
- Send compressed image data to explicitly enabled vision-capable OpenAI-compatible models
  only after a per-upload confirmation
- Browse, search, edit, copy, pin, OCR, translate, scan, ask AI, reveal, and delete captures
  from Screenshot History, with grid and list layouts also available from the unified History tab

Screenshots require Screen Recording permission. Region selection supports multiple
displays and `Esc` cancels an active capture. Screen Recording and Accessibility
permissions are independent. macOS associates Screen Recording approval with the
application identity; unsigned or frequently rebuilt ad-hoc apps may require approval
again, while a consistently signed app retains a stable permission identity.

## Desktop Whiteboard

The desktop whiteboard is off by default. Enable it from Preferences -> Whiteboard,
then use `Option+Shift+W`, the launcher commands, or the existing menu bar item to
enter and leave editing mode.

- Draw rectangles, ellipses, diamonds, arrows, lines, freehand strokes, and text
- Select, move, resize, rotate, duplicate, copy, paste, erase, undo, and redo elements
- Pan, zoom, fit the canvas, import images, and send clipboard or screenshot images to it
- Import and export Excalidraw documents while preserving unsupported fields; export PNG and SVG
- Choose whether idle content is hidden or remains visible and whether captures include board content
- Choose a transparent or paper-white editing surface independently from dots/grid guides, and use a transparent or paper-white PNG/SVG export background
- Keep the feature fully dormant while disabled: no board window, workspace read, or hotkey registration

The board uses one active display at a time. Its local workspace and image resources are stored under:

```text
~/Library/Application Support/<Meow or Miao>/Whiteboards/
```

## System Monitor

The system monitor is off by default. Enable it from Preferences -> System Monitor;
it runs in its own menu bar item so it can be enabled independently from the main Meow
status item.

- Displays CPU, memory, GPU memory, network, disk, battery, and thermal metrics
- Lets you choose the menu bar style, sampling interval, history duration, and visible metrics
- Shows compact metric cards, recent CPU/memory summaries, and IPv4 LAN/public addresses
- Provides one-click copy buttons for the displayed addresses with visual confirmation
- Keeps the feature dormant while disabled and refreshes public IPv4 lookup failures with backoff

The system monitor does not require a separate permission. Local and public address values are
limited to IPv4; IPv6 addresses are intentionally not displayed.

## File Uploads

Configure S3-compatible file hosting from Preferences -> File Hosting.

- Supports saved configurations for AWS S3, Cloudflare R2, MinIO, and custom S3-compatible endpoints
- Stores Secret Access Keys in macOS Keychain; non-secret configuration remains in Meow settings
- Uploads screenshots from the post-capture action bar or an independent region-capture shortcut
- Uploads clipboard files or images from the Launcher command
- Accepts files dragged onto the menu bar icon without adding upload items to its context menu
- Streams regular uploads and switches to multipart uploads for files of 64 MB or larger
- Supports custom-domain, public-bucket, and expiring presigned links in URL, Markdown, or HTML format
- Keeps local upload history with thumbnails, source labels, refreshed presigned links, and optional remote-object deletion
- Copies the resulting link and shows an in-app completion banner after upload

Upload history is stored under:

```text
~/Library/Application Support/Meow/Uploads/
```

S3-compatible providers differ in endpoint, signing, public access, and multipart behavior.
Use Test Upload to validate both object upload and final link access before relying on a configuration.

## Screen Recording

Configure recording from Preferences -> Recording, then use launcher commands or the
independent global shortcuts.

- Records displays, regions, single or multiple windows, applications, system audio, and connected iPhone/iPad capture devices
- Supports H.264, HEVC, HEVC with Alpha, SDR/HDR, Retina resolution, and up to 60 FPS from Preferences
- Captures system audio and a selected microphone as mixed or separate tracks
- Adds an optional movable camera overlay with rectangle, rounded, or circle shapes, native mouse-click highlights, a pointer magnifier, and PNG frame capture
- Supports desktop, transparent, or custom solid-color backgrounds for filtered window content
- Shows recording duration and pause/stop controls in the menu bar and a floating control panel
- Saves to `~/Movies/Meow/` by default and indexes metadata and thumbnails under
  `~/Library/Application Support/Meow/Recordings/`
- Provides searchable history with grid/list layouts, Finder reveal, deletion, and count/age/storage retention policies
- Opens a floating completion preview with playback and non-destructive start/end trimming
- Preserves recovery metadata for interrupted recordings and scans it on the next launch

Screen, region, window, application, and system-audio capture require Screen Recording
permission. Microphone and camera capture request their own permissions. HDR forces HEVC
in MOV; transparent output requires HEVC with Alpha in MOV and is most useful for window
or application capture.

## Authenticator

Configure the TOTP authenticator from Preferences -> Authenticator.

- Stores account secrets in macOS Keychain, not Meow settings
- Supports manual Base32 secrets and standard `otpauth://` URLs
- Imports Meow backups, token arrays, and Keyden vault JSON
- Exports a versioned JSON backup after an explicit plaintext-secret warning
- Excludes copied codes and imported secrets from Meow clipboard history
- Can sync individual accounts through iCloud Keychain

iCloud Keychain sync requires a stable Apple-signed build with the required entitlement. Unsigned or ad-hoc builds keep accounts local and report the missing capability. Exported JSON contains plaintext TOTP secrets and must be stored securely.

## Offline Speech Recognition

Offline speech recognition is available in the Miao voice edition. Configure it from Preferences -> Speech.

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

## Offline Speech Synthesis

Offline speech synthesis is available in the Miao voice edition. Configure it from Preferences -> Speech -> Synthesis.

- Uses the existing sherpa-onnx runtime with the Matcha Chinese-English model
- Supports Chinese, English, mixed-language text, and a stable single voice
- Downloads the approximately 140 MB model and vocoder only after confirmation
- Supports play, pause, resume, stop, and WAV export
- Adds read-aloud actions for selected text, clipboard entries, and launcher commands when enabled
- Configures the read-selection hotkey from Preferences -> Speech -> Synthesis
- Reading selected text requires Accessibility permission
- Runs fully offline after the model is installed

The TTS model is stored under:

```text
~/Library/Application Support/Meow/Models/TTS/
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
- Whether the configured model supports image input
- Maximum uploaded image edge and JPEG quality

Chat history is stored locally under:

```text
~/Library/Application Support/Meow/AIChats/
```

API keys remain in Meow's local settings storage. Chat history can be disabled, cleared,
or opened from the AI settings screen. Images remain local until the user invokes Ask AI;
Meow shows the destination endpoint and compression settings before each upload.

## Project Structure

- `Sources/App/MeowApp.swift`: app lifecycle and window management
- `Sources/ViewModels/LauncherViewModel.swift`: search and ranking logic
- `Sources/Views/`: launcher, AI chat, authenticator, preferences, translation, and UI components
- `Sources/Theme.swift`: theme palette system
- `Sources/Services/`: hotkey, status item, auto-launch, clipboard, file upload, translation, system monitor, speech recognition, authenticator, AI chat, and persistence
- `Sources/Services/SystemMonitor/`: metric collectors, sampling actor, history, and monitor models
- `Sources/Models/`: app, clipboard, file hosting, authenticator, and settings models
- `Sources/Resources/`: localization resources
- `Tests/`: Swift Testing coverage

## Notes

- Run `swift test`, `swift build`, and `swift build -c release` before submitting changes.
- For system monitor changes, manually check enable/disable, independent menu bar behavior, module visibility, compact popover layout, IPv4-only address display, copy feedback, and English/Chinese localization.
- Authenticator changes require manual checks for Keychain storage, clipboard-history exclusion, JSON warnings, and local-only sync fallback.
- For AI changes, manually check configured and unconfigured states, model fetch/manual entry, Enter send, Shift+Enter newline, chat history, and opening the history folder.
- For health reminder changes, manually check timer start/pause/resume, break start/skip/done, daily goal progress, activity-paused countdown, and menu bar calendar controls.
- For keyboard overlay changes, manually check Accessibility permission denied/granted states, hotkey conflict behavior, dragging/resetting the overlay, and non-US keyboard layouts.
- For file-upload changes, manually check AWS S3, R2, and MinIO configurations, public and presigned links, files above 64 MB, cancellation, clipboard cleanup, drag-and-drop, remote deletion, and Keychain credential handling.
- See [DEVELOPMENT.md](DEVELOPMENT.md) for development details.
