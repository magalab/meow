# Contributing to Meow

Thank you for your interest in contributing to Meow! This document provides guidelines and instructions for contributing.

## Development Setup

### Prerequisites
- macOS 14+
- Swift 5.9+
- Xcode Command Line Tools

### Build & Run

```bash
# Debug build
swift build

# Release build
swift build -c release

# Create distributable DMG
bash scripts/build-dmg.sh
```

## Coding Standards

### Swift Style
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use 4-space indentation (Xcode default)
- Keep lines under 100 characters when reasonable
- Use descriptive variable and function names

### Comments
- Document public APIs with doc comments (`///`)
- Explain complex logic with inline comments
- Keep comments up-to-date with code changes

### Code Organization
- Group related functionality together
- Keep files focused on a single responsibility
- Use MARK: comments to organize large files

```swift
// MARK: - Lifecycle
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Utilities
```

## Making Changes

### Branch Naming
- `feature/description` for new features
- `fix/description` for bug fixes
- `docs/description` for documentation changes
- `refactor/description` for code refactoring

### Commit Messages
Write clear, descriptive commit messages:

```
feat: add command palette search

- Implement fuzzy search algorithm
- Add search highlighting
- Update UI components
```

### Pull Request Process

1. Fork and create a feature branch
2. Make your changes with clear commits
3. Ensure code compiles: `swift build`
4. Optionally validate release build: `swift build -c release`
5. Test your changes thoroughly (see checklist below)
6. Submit a PR with:
   - Clear description of changes
   - Reference related issues
   - Screenshots if UI changes

## Localization

The app supports multiple languages. String resources are in `Sources/Resources/`:
- `en.lproj/Localizable.strings` - English
- `zh-Hans.lproj/Localizable.strings` - Simplified Chinese

### Adding New Strings

1. Add to `L10n` enum in `Sources/Strings.swift`:
```swift
static var myNewString: String {
    loc("my_new_key")
}
```

2. Add to both `.lproj/Localizable.strings` files

## Validation Checklist

- Build debug: `swift build`
- Build release: `swift build -c release`
- Package app: `bash scripts/build-dmg.sh`
- Verify these behaviors manually:
  - launcher show/hide and search
  - app launch
  - preferences open/update
  - language switching
  - hotkey recording and activation
  - status bar and Dock visibility toggles

## Testing

- Test UI changes on actual macOS hardware when possible
- Test with different language settings
- Test keyboard shortcuts and hotkeys
- Verify app auto-launch functionality

## Documentation

- Update README for new features
- Document configuration options
- Add inline code comments for complex logic

## Reporting Issues

Include:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots/logs if applicable

## Questions?

Feel free to open an issue or discussion for questions about the codebase.

Happy coding!
