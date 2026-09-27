# Repository Guidelines

## Project Structure & Module Organization
Meow is a Swift 6 Package executable app (`Package.swift`) targeting macOS 15+.
The package builds two editions: the default `Meow` edition and the optional
`Miao` voice edition selected with `MEOW_EDITION=voice`.
- `Sources/App/`: app lifecycle and AppKit/SwiftUI startup (`MeowApp.swift`)
- `Sources/ViewModels/`: launcher logic and ranking (`LauncherViewModel.swift`)
- `Sources/Views/` and `Sources/Views/Components/`: UI screens, translation panel, AI chat, authenticator, capture, recording, system monitor, speech, preferences, and reusable view parts
- `Sources/Services/`: system integrations (clipboard, settings, launch history, capture, recording, file upload, translation capture, AI chat, authenticator storage/sync, health reminder, and voice-edition speech recognition)
- `Sources/Services/Uploaders/`: backend-neutral upload protocol plus the Soto-based S3 uploader
- `Sources/Models/`: app, clipboard, file hosting, AI settings, authenticator, capture, recording, speech, system monitor, and health reminder models
- `Modules/WhiteboardFeature/`: standalone whiteboard feature module, resources, and tests
- `Packages/MeowSpeech/`: local voice-only package containing speech contracts and the extracted SenseVoice CoreML backend
- `Sources/Resources/{en.lproj,zh-Hans.lproj}`: localization strings
- `Tests/`: Swift Testing coverage for settings compatibility, whiteboard, capture, recording, uploads, AI chat, speech recognition, TOTP generation, OTPAuth parsing, JSON backup/import, health reminder persistence, launch history scoring, and sync merging
- `~/Library/Application Support/Meow/AIChats/`: runtime AI chat history storage (`index.json` plus per-conversation JSON files)
- `~/Library/Application Support/Meow/Uploads/`: upload history index and generated image thumbnails
- `~/Library/Application Support/Meow/Models/ASR/`: downloaded voice-edition SenseVoice model artifacts; model files are not committed
- Health reminder daily progress is stored locally in `UserDefaults` under `meow.health.reminder.records`.
- Authenticator secrets are stored in macOS Keychain. Optional iCloud Keychain sync requires an appropriately signed build and entitlements.
- `scripts/`: packaging helpers (`build-dmg.sh`, `create-icon.sh`)
- `.github/workflows/`: CI, release, and Homebrew tap automation

Text-to-speech and Sherpa runtime integration have been removed. Do not add
TTS-specific settings, services, model stores, or dependencies unless the
product scope explicitly changes.

## Build, Test, and Development Commands
- `swift build`: debug build for local development.
- `swift test`: run the Swift Testing suite.
- `swift build -c release`: release build used by packaging and CI.
- `.build/debug/Meow`: run the debug binary after building.
- `MEOW_EDITION=voice swift build --product Miao`: build the voice edition.
- `MEOW_EDITION=voice swift test`: run the voice-edition test suite.
- `MEOW_EDITION=voice swift build -c release --product Miao`: build the voice release binary.
- `.build/debug/Miao`: run the voice-edition debug binary after building.
- `bash scripts/build-dmg.sh`: create `dist/Meow_<version>_<arch>.dmg`.
- `MEOW_EDITION=voice bash scripts/build-dmg.sh`: create the Miao voice DMG.
- `APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh`: override bundle identifier.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines and keep code readable over cleverness.
- Indentation: 4 spaces for `*.swift` (`.editorconfig`); 2 spaces for YAML/JSON/shell.
- Prefer `PascalCase` type/file names and one primary type per file.
- Use `// MARK:` blocks for larger files.
- Respect Swift 6 concurrency checks. AppKit/SwiftUI-facing services and UI caches should stay on `@MainActor` unless there is a clear thread-safety boundary.
- Keep voice-only application sources and dependencies behind `MEOW_VOICE` / `MEOW_EDITION=voice`; the default edition must build without `Packages/MeowSpeech`.
- Keep the extracted speech package self-contained. Model artifacts belong in the runtime model directory and must be pinned and SHA-256 verified, not checked into the repository.
- Keep CI hygiene intact: no trailing whitespace, no tab-indented Swift lines, and no `TODO`/`FIXME` left in `Sources/`.

## Testing Guidelines
Validate changes with:
1. `swift test`
2. `swift build`
3. `swift build -c release`
4. For voice-related changes, also run `MEOW_EDITION=voice swift test` and `MEOW_EDITION=voice swift build -c release --product Miao`.
5. For standalone speech-package changes, run `swift test --package-path Packages/MeowSpeech`.
6. When a local model is available, run the opt-in SenseVoice inference smoke test with `MEOW_SENSEVOICE_MODEL_DIR` set; model fixtures are intentionally not committed.
7. Manual checks: launcher search, app launch, preferences changes, language switching, hotkey behavior, translation hotkey/selection capture, status bar and Dock toggles.
For voice changes, also test Miao speech permission states, model download/recovery, recording cancellation, transcription, history, pasteboard restoration, and first-load latency.
For UI/localization changes, test both English and Simplified Chinese resources.
For translation changes, test on macOS 15+ with Accessibility permission granted and denied; verify selected text capture and pasteboard restoration.
For AI changes, test configured and unconfigured states, Ask AI command, clipboard Ask AI action, Enter send vs Shift+Enter newline, model fetch/manual model entry, API key show/copy, AI settings deep-link, chat history toggle, clear-history confirmation, and opening the chat history folder.
For AI persistence changes, verify history files under `~/Library/Application Support/Meow/AIChats/`. Keep AI API keys in Keychain; keep non-secret AI settings in the local settings blob. Never store API keys in `UserDefaults`, settings JSON, or upload history.
For file upload changes, test AWS S3, Cloudflare R2, and MinIO configurations; custom-domain, public-bucket, and presigned links; small streaming and 64 MB+ multipart uploads; cancellation and network failures; clipboard temporary-file cleanup; status-item drag-and-drop; history refresh and optional remote deletion. Keep Secret Access Keys in Keychain, never settings or upload history JSON.
For health reminder changes, test start/pause/resume, manual break start, skip, done, daily progress persistence, activity-paused countdown, gentle vs strict break window behavior, and menu bar calendar controls.
For authenticator changes, test disabled/enabled states, manual secret and `otpauth://` import, unsupported algorithm rejection, code copying without clipboard-history retention, JSON import/export warnings, duplicate handling, deletion, and launcher presentation. Keep secrets in Keychain, never `UserDefaults`.
For authenticator sync changes, test local-only fallback, missing-entitlement errors, first-enable merge, offline additions/deletions, deletion tombstones, manual refresh, and re-enabling sync without resurrecting deleted accounts. Real cross-device validation requires a signed build with iCloud Keychain capability.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit-style prefixes (`feat:`, `fix:`, `refactor:`, `chore:`). Use concise imperative subjects, e.g., `fix: prevent duplicate clipboard entries`.

PRs should:
- Use the `.github/pull_request_template.md` sections.
- Link related issues (`Fixes #...`).
- Describe testing performed.
- Include screenshots for visible UI changes.
- Update docs and both `.lproj` files when adding user-facing strings.
