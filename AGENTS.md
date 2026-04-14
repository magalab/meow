# Repository Guidelines

## Project Structure & Module Organization
Meow is a Swift Package executable app (`Package.swift`) targeting macOS 14+.
- `Sources/App/`: app lifecycle and AppKit/SwiftUI startup (`MeowApp.swift`)
- `Sources/ViewModels/`: launcher logic and ranking (`LauncherViewModel.swift`)
- `Sources/Views/` and `Sources/Views/Components/`: UI screens and reusable view parts
- `Sources/Services/`: system integrations (clipboard, settings, launch history)
- `Sources/Models/`: app and clipboard models
- `Sources/Resources/{en.lproj,zh-Hans.lproj}`: localization strings
- `scripts/`: packaging helpers (`build-dmg.sh`, `create-icon.sh`)
- `.github/workflows/`: CI, release, and Homebrew tap automation

## Build, Test, and Development Commands
- `swift build`: debug build for local development.
- `swift build -c release`: release build used by packaging and CI.
- `.build/debug/Meow`: run the debug binary after building.
- `bash scripts/build-dmg.sh`: create `dist/Meow_<version>_<arch>.dmg`.
- `APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh`: override bundle identifier.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines and keep code readable over cleverness.
- Indentation: 4 spaces for `*.swift` (`.editorconfig`); 2 spaces for YAML/JSON/shell.
- Prefer `PascalCase` type/file names and one primary type per file.
- Use `// MARK:` blocks for larger files.
- Keep CI hygiene intact: no trailing whitespace, no tab-indented Swift lines, and no `TODO`/`FIXME` left in `Sources/`.

## Testing Guidelines
There is currently no SwiftPM test target. Validate changes with:
1. `swift build`
2. `swift build -c release`
3. Manual checks: launcher search, app launch, preferences changes, language switching, hotkey behavior, status bar and Dock toggles.
For UI/localization changes, test both English and Simplified Chinese resources.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit-style prefixes (`feat:`, `fix:`, `refactor:`, `chore:`). Use concise imperative subjects, e.g., `fix: prevent duplicate clipboard entries`.

PRs should:
- Use the `.github/pull_request_template.md` sections.
- Link related issues (`Fixes #...`).
- Describe testing performed.
- Include screenshots for visible UI changes.
- Update docs and both `.lproj` files when adding user-facing strings.
