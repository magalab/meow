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

## CI (GitHub Actions)

CI runs on PRs to `main`/`develop` (`.github/workflows/build.yml`):
- Validates `Package.swift` with `swift package describe`
- Checks formatting hygiene: no trailing whitespace, no tab indentation in Swift files
- Checks for `TODO`/`FIXME` comments in `Sources/` (fails if any found)
- Builds debug (must be warning-free) and release

## AGENTS.md

This repo also has an `AGENTS.md` with coding style (`.editorconfig`: 4-space Swift, 2-space YAML/JSON/shell), Conventional Commit prefixes (`feat:`, `fix:`, `refactor:`, `chore:`), and PR template requirements. Both files apply — CLAUDE.md focuses on architecture and build commands.

## Architecture

### App Lifecycle & Windows
- `Sources/App/MeowApp.swift`: `@main` entry point (`MeowApp`) + `AppDelegate`
  - AppDelegate owns all service instances and coordinates settings changes
  - Four windows: `LauncherPanel` (search), `LauncherPanel` (translation), `NSWindow` (preferences), `NSWindow` (AI chat)
  - Calendar popover (`NSPopover`) attached to the status item button
  - Global mouse/key monitors dismiss panels on outside click; escape dismisses translation
  - Cmd+, shortcut opens preferences from anywhere via local key monitor

### Models (Sources/Models/)
- `AppSettings.swift`: All user preferences persisted via `UserDefaults` including `AISettings` (endpoint, apiKey, model, systemPrompt, chatHistoryEnabled), `DateIconStyle` (7 variants: pawPrint, outlinedDay, roundedOutlineDay, dayOnly, monthDay, weekdayDay, lunarDate), `DockIconStyle` (default/calendar/flat), `AppLanguage`, `AppTheme`
- `AppModels.swift`: `AppEntry` (launchable app), `CommandEntry` (built-in command), `SearchItem` enum unifying both
- `ClipboardModels.swift`: `ClipboardEntry`, `ClipboardContent` enum (text/image/file/unsupported)

### View Models
- `Sources/ViewModels/LauncherViewModel.swift`: `LauncherViewModel`
  - Substring search over apps + built-in commands + clipboard entries
  - Scoring: text match quality (exact > prefix > substring) + launch history recency/frequency
  - Built-in commands: "Preferences", "AI Chat", "Quit Meow"
  - Clipboard actions: copy item to pasteboard, paste into frontmost app via CGEvent simulated ⌘V

### Services (Sources/Services/)
- `SettingsStore.swift`: UserDefaults persistence for `AppSettings`
- `LaunchHistoryStore.swift`: Records app launches, provides recency/frequency scoring boost
- `ClipboardService.swift`: Monitors clipboard changes via Timer, stores last 50 entries with optional image caching; also handles pasteboard writes and simulated ⌘V paste via CGEvent
- `SystemServices.swift`: `DockService` (dock icon toggle), `DockIconService` (dynamic dock icon with calendar/date rendering), `StatusItemService` (menu bar with date-themed icon, toggle states, calendar popover trigger), `AppDiscoveryService` (enumerates /Applications, /System/Applications, ~/Applications), `AutoLaunchService` (login item), `HotkeyService` (multi-hotkey via Carbon `RegisterEventHotKey` with signature `MEOW`)
- `TranslationService.swift`: Captures selected text via Accessibility API (`AXUIElementCopyAttributeValue`), falls back to simulating ⌘C to get text from clipboard
- `AIChatService.swift`: OpenAI-compatible chat completions API client (configurable endpoint, model list fetching, chat streaming); endpoint normalization handles `/v1`, `/v1/chat/completions`, and bare URLs
- `AIChatHistoryStore.swift`: Persists conversations as individual JSON files in `~/Library/Application Support/Meow/AIChats/conversations/` plus an `index.json`; max 50 conversations, 80 messages each, 100k char message limit; supports legacy migration from UserDefaults and flat-file formats
- `CalendarService.swift`: Singleton that computes lunar calendar dates, solar terms (via `solar_terms.json` resource), Chinese holidays, zodiac/stem-branch year names; bilingual (en/zh)
- `CalendarService.swift` also defines `CalendarEventService` (`@MainActor ObservableObject`): loads daily events via EventKit with permission handling (idle → loading → loaded/denied/restricted/failed)

### Views (Sources/Views/)
- `LauncherView.swift`: Search bar + `LazyVStack` results list in a floating gradient panel, with clipboard history drawer
- `PreferencesView.swift`: Segmented sections (General, Appearance, AI) with hotkey recorders, theme picker, AI configuration, chat history management
- `TranslationView.swift`: Floating translation panel using `TranslationSession` (macOS 15+), auto-detects source language with `NLLanguageRecognizer`, switches between en/zh-Hans
- `AIChatView.swift`: Chat panel with conversation sidebar, message list, streaming responses, markdown rendering; creates fresh conversations via launcher or direct window
- `Components/ItemComponents.swift`: Search result row rendering (app icon, clipboard preview, command chip)
- `Components/ActionMenu.swift`: Context menu for app/clipboard entries
- `Components/CalendarView.swift`: Calendar popover with month grid, lunar dates, solar terms, holidays, daily EventKit events
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
- **AI Chat**: Uses OpenAI-compatible chat completions API (any endpoint). Model list fetched from `/v1/models`. Endpoint normalization: bare `/v1` or empty path auto-suffixes `/chat/completions`. Settings stored in `AISettings` inside `AppSettings`. Chat history persisted as individual JSON files per conversation (max 50 conversations, 80 messages each, messages capped at 100k chars). Supports legacy migration from UserDefaults and flat JSON file formats. History can be toggled on/off; disabling clears all persisted data.
- **Calendar**: Lunar calendar via `Calendar(identifier: .chinese)` plus custom solar-term lookup from `solar_terms.json` (pre-computed JSON keyed by year). Holidays: New Year, Labour Day, National Day, Spring Festival, Dragon Boat Festival, Mid-Autumn Festival, Qingming — all bilingual. Calendar events via EventKit with permission states (idle/loading/loaded/denied/restricted/failed). Popover is a transient `NSPopover` attached to the status item button.
- **Dynamic dock icon**: `DockIconService` renders the dock icon dynamically based on `DockIconStyle` (default/calendar/flat) + current date. Calendar style shows the day number; other styles include paw print, outlined day, month+day, weekday+day, and lunar date. Status item similarly supports date-themed icons via `DateIconStyle`.
