# Development Guide

## Project Structure

```
├── Sources/
│   ├── MeowApp.swift        # App entry point and AppDelegate
│   ├── Models.swift         # Data models
│   ├── Views.swift          # SwiftUI components
│   ├── Services.swift       # System services
│   ├── LauncherViewModel.swift # Search/ranking and actions
│   ├── Strings.swift        # Localization manager
│   └── Resources/
│       ├── en.lproj/        # English strings
│       └── zh-Hans.lproj/   # Chinese strings
├── Package.swift            # Swift Package manifest
├── scripts/
│   ├── build-dmg.sh         # Create distributable DMG
│   └── create-icon.sh       # Generate app icon
```

## Architecture

### App Entry & Lifecycle
- **MeowApp.swift**: App entry and AppDelegate
  - Sets up AppKit windows (launcher, preferences)
  - Manages system services (hotkey, status item)
  - Handles language switching and settings

### State Management
- **Models.swift**: Data structures
  - `AppSettings`: Persisted user preferences
  - `AppLanguage`: Language selection
  - `CommandEntry`, `AppEntry`: Search results

- **LauncherViewModel.swift**: Search & launch logic
  - Command/app matching with scoring
  - App discovery
  - Launch history ranking

### UI Layer
- **Views.swift**: SwiftUI components
  - `LauncherView`: Main search panel (borderless NSPanel)
  - `PreferencesView`: Settings window
  - Reactive to language changes via `@ObservedObject`

### Services
- **Services.swift**:
  - `HotkeyService`: Carbon-based global hotkey registration
  - `StatusItemService`: Menu bar integration
  - `DockService`: Dock visibility control
  - `DiscoveryService`: App/command enumeration

### Localization
- **Strings.swift**:
  - `LanguageManager`: Runtime bundle switching
  - `L10n`: Localized string accessors
  - Falls back to English if key not found

## Building

### Debug Build
```bash
swift build
```

### Release Build
```bash
swift build -c release
```

### Create DMG Package
```bash
bash scripts/build-dmg.sh
```

This will:
1. Generate icon from `logo.png` if needed
2. Build release binary
3. Create `.app` bundle with resources
4. Create `.dmg` installer

Notes:
- Minimum supported macOS version is 14.0 (`Package.swift` and generated `Info.plist`).
- If `logo.png` is missing and `AppIcon.icns` does not exist, icon generation will fail.

## Coding Guidelines

### File Naming
- Use PascalCase for files: `MeowApp.swift`, `LauncherView.swift`
- One main type per file (exception: small related types)

### Code Organization
```swift
// MARK: - Type Definition
struct MyType {
    // MARK: - Properties
    var property: String
    
    // MARK: - Initialization
    init() { }
    
    // MARK: - Public Methods
    func doSomething() { }
    
    // MARK: - Private Methods
    private func helper() { }
}
```

### SwiftUI Views
- Use `.id()` modifier when views depend on Observable objects
- Prefer computed properties for dynamic content
- Extract complex views into separate structs

### Performance
- Cache expensive computations in `@State` or `@StateObject`
- Use `onReceive` instead of polling
- Lazy evaluate commands/apps

## Localization

### Adding Strings
1. Add to `L10n` enum in `Strings.swift`:
```swift
static var myString: String {
  loc("my_key")
}
```

2. Add keys to both `.lproj` files:
```
"my_key" = "English text";
```

### Changing Language at Runtime
```swift
LanguageManager.shared.apply(.chinese)
```

The app will:
- Swap bundle to `zh-Hans.lproj`
- Notify all observers via `@Published refreshToken`
- Trigger view rebuilds via `.id()` modifiers

## Testing

There is currently no SwiftPM test target in this package.
Use the manual checklist below plus build verification commands.

### Manual Testing Checklist
- [ ] App launches and shows launcher panel
- [ ] Search works with fuzzy matching
- [ ] Launching an app works
- [ ] Preferences window opens/closes
- [ ] Language switching works
- [ ] Custom hotkey recording works
- [ ] Status bar menu functional
- [ ] Auto-launch preference works
- [ ] Dock visibility toggle works

### Build Verification
```bash
# Check compilation
swift build -v

# Check release compilation
swift build -c release

# Build DMG
bash scripts/build-dmg.sh

# Verify app bundle
ls -la dist/Meow.app/Contents/
```

## Debugging

### Enable Logging
Add `print()` statements and run with:
```bash
swift build && .build/debug/Meow
```

### Check Resources
```bash
# Verify .lproj bundles
ls -la dist/Meow.app/Contents/Resources/

# Check Localizable.strings
strings dist/Meow.app/Contents/Resources/en.lproj/Localizable.strings
```

### View System Events
In Terminal, monitor app behavior:
```bash
log stream --predicate 'process == "Meow"'
```

## Common Tasks

### Add a New Command
1. Add command entry in `LauncherViewModel.commands`
2. Handle command ID in `LauncherViewModel.run(_:)`
3. Add localization keys in both `Localizable.strings` files

### Add a Menu Bar Item
1. Update `StatusItemService` in `Services.swift`
2. Add to localization strings
3. Implement action handler

### Change Preferences Layout
1. Edit `PreferencesView` in `Views.swift`
2. Update `AppSettings` model in `Models.swift`
3. Handle in `AppDelegate.apply(settings:)` if system interaction needed

## Resources

- [Swift Package Manager](https://swift.org/package-manager/)
- [SwiftUI Documentation](https://developer.apple.com/xcode/swiftui/)
- [AppKit Documentation](https://developer.apple.com/documentation/appkit)
- [localization Best Practices](https://developer.apple.com/localization/)

## Getting Help

- Check existing issues and discussions
- Review [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
- Open a new issue with detailed description
