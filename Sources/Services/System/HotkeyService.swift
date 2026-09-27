import Carbon
import Foundation

// Event-handler callbacks dispatch registry access to the main thread; the
// unchecked conformance only crosses the C callback boundary.
final class HotkeyService: @unchecked Sendable {
    enum RegistrationResult: Equatable {
        case registered
        case failed(OSStatus)

        var isRegistered: Bool {
            if case .registered = self { return true }
            return false
        }
    }

    private struct RegisteredHotkey {
        let keyCode: UInt32
        let modifiers: UInt32
        let ref: EventHotKeyRef
        let pressedAction: () -> Void
        let releasedAction: (() -> Void)?
    }

    private var hotKeys: [UInt32: RegisteredHotkey] = [:]
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        unregister()
    }

    /// Registers (or replaces) the launcher-toggle hotkey (id = 1).
    func registerToggleHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 1, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    /// Registers (or replaces) the Finder hotkey (id = 20).
    func registerFinderHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 20, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    /// Registers (or replaces) the translate hotkey (id = 2).
    func registerTranslateHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 2, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    /// Registers (or replaces) the selected-text actions hotkey (id = 17).
    func registerTextActionsHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 17, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    /// Registers (or replaces) the hold-to-record speech hotkey (id = 3).
    func registerSpeechHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        pressedAction: @escaping () -> Void,
        releasedAction: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(
            id: 3,
            keyCode: keyCode,
            modifiers: modifiers,
            pressedAction: pressedAction,
            releasedAction: releasedAction
        )
    }

    func unregisterSpeechHotkey() {
        unregisterHotkey(id: 3)
    }

    func registerScreenshotRegionHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 4, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotScrollingHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 19, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotWindowHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 5, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotEditHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 7, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotDisplayHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 6, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingDisplayHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 8, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingRegionHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 9, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingWindowHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 10, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingPauseHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 11, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingStopHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 12, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func unregisterRecordingHotkeys() {
        for id: UInt32 in 8...14 {
            unregisterHotkey(id: id)
        }
    }

    func registerRecordingFrameHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 13, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingMagnifierHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 14, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerUploadHotkey(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> RegistrationResult {
        registerHotkey(id: 16, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func unregisterUploadHotkey() {
        unregisterHotkey(id: 16)
    }

    func registerWhiteboardHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 18, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func unregisterWhiteboardHotkey() {
        unregisterHotkey(id: 18)
    }

    func unregisterScreenshotHotkeys() {
        unregisterHotkey(id: 4)
        unregisterHotkey(id: 5)
        unregisterHotkey(id: 6)
        unregisterHotkey(id: 7)
        unregisterHotkey(id: 19)
    }

    func unregister() {
        for hotKey in hotKeys.values { UnregisterEventHotKey(hotKey.ref) }
        hotKeys.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func handleHotkey(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return noErr }
        let callbackID = hotKeyID.id
        let eventKind = GetEventKind(event)
        DispatchQueue.main.async { [weak self] in
            guard let hotkey = self?.hotKeys[callbackID] else { return }
            if eventKind == UInt32(kEventHotKeyReleased) {
                hotkey.releasedAction?()
            } else {
                hotkey.pressedAction()
            }
        }
        return noErr
    }

    // MARK: - Private

    private func registerHotkey(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        pressedAction: @escaping () -> Void,
        releasedAction: (() -> Void)? = nil
    ) -> RegistrationResult {
        if eventHandlerRef == nil {
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotkeyHandler,
                eventTypes.count,
                &eventTypes,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerRef
            )
            guard status == noErr else {
                MeowLog.hotkey.error("Failed to install hotkey event handler: \(status, privacy: .public)")
                return .failed(status)
            }
        }

        if let existing = hotKeys[id],
           existing.keyCode == keyCode,
           existing.modifiers == modifiers
        {
            hotKeys[id] = RegisteredHotkey(
                keyCode: keyCode,
                modifiers: modifiers,
                ref: existing.ref,
                pressedAction: pressedAction,
                releasedAction: releasedAction
            )
            return .registered
        }

        let previous = hotKeys[id]
        if let previous {
            UnregisterEventHotKey(previous.ref)
            hotKeys[id] = nil
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("MEOW"), id: id)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr, let ref = hotKeyRef {
            hotKeys[id] = RegisteredHotkey(
                keyCode: keyCode,
                modifiers: modifiers,
                ref: ref,
                pressedAction: pressedAction,
                releasedAction: releasedAction
            )
            return .registered
        }

        if let previous {
            restorePreviousHotkey(previous, id: id)
        }

        MeowLog.hotkey.error(
            "Failed to register hotkey id=\(id, privacy: .public): \(registerStatus, privacy: .public)"
        )
        return .failed(registerStatus)
    }

    private func restorePreviousHotkey(_ previous: RegisteredHotkey, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("MEOW"), id: id)
        var restoredRef: EventHotKeyRef?
        let restoreStatus = RegisterEventHotKey(
            previous.keyCode,
            previous.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &restoredRef
        )

        if restoreStatus == noErr, let restoredRef {
            hotKeys[id] = RegisteredHotkey(
                keyCode: previous.keyCode,
                modifiers: previous.modifiers,
                ref: restoredRef,
                pressedAction: previous.pressedAction,
                releasedAction: previous.releasedAction
            )
        } else {
            MeowLog.hotkey.error(
                "Failed to restore previous hotkey id=\(id, privacy: .public): \(restoreStatus, privacy: .public)"
            )
        }
    }

    private func unregisterHotkey(id: UInt32) {
        guard let hotkey = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(hotkey.ref)
    }
}

private let hotkeyHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else { return noErr }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    return service.handleHotkey(eventRef)
}

private func fourCharCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for scalar in string.uppercased().unicodeScalars.prefix(4) {
        result = (result << 8) + scalar.value
    }
    return result
}
