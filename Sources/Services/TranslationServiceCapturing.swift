import AppKit
@preconcurrency import ApplicationServices
import Foundation

@MainActor
protocol TranslationServiceCapturing {
    func isAccessibilityTrusted(promptForPermission: Bool) -> Bool
    func captureSelectedTextViaAccessibility() -> String?
    func captureSelectedTextViaTemporaryCopy() -> String?
}

@MainActor
final class SystemTranslationServiceCapturing: TranslationServiceCapturing {
    private struct PasteboardItemSnapshot {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    func isAccessibilityTrusted(promptForPermission: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptForPermission] as CFDictionary
        )
    }

    func captureSelectedTextViaAccessibility() -> String? {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedReference
        ) == .success,
            let focusedValue = focusedReference,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement // swiftlint:disable:this force_cast
        var selectedReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedReference
        ) == .success,
            let text = selectedReference as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return text
    }

    func captureSelectedTextViaTemporaryCopy() -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = snapshotPasteboardItems()
        let originalChangeCount = pasteboard.changeCount

        simulateCopy()

        let deadline = Date().addingTimeInterval(0.35)
        var copiedText: String?
        while Date() < deadline {
            if pasteboard.changeCount != originalChangeCount {
                copiedText = pasteboard.string(forType: .string)
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        restorePasteboardItems(from: savedItems)

        guard let text = copiedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }
        return text
    }

    private func simulateCopy() {
        InternalInputEventSuppressor.suppress(for: 0.25)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) // C key
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func snapshotPasteboardItems() -> [PasteboardItemSnapshot] {
        NSPasteboard.general.pasteboardItems?.compactMap { item in
            let values = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            guard !values.isEmpty else { return nil }
            return PasteboardItemSnapshot(values: values)
        } ?? []
    }

    private func restorePasteboardItems(from snapshots: [PasteboardItemSnapshot]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restoredItems = snapshots.map { snapshot in
            let item = NSPasteboardItem()
            for value in snapshot.values {
                item.setData(value.data, forType: value.type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
