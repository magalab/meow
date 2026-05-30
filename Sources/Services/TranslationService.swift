import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Captures text for translation.
///
/// Grabs the selected text from the frontmost app via the Accessibility API.
/// Falls back to a temporary copy operation when direct selection access is
/// unavailable, then restores the original pasteboard contents.
@MainActor
final class TranslationService: ObservableObject {
    private struct PasteboardItemSnapshot {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    @Published private(set) var pendingText: String = ""

    /// True when the last capture attempt found that AX permission is missing.
    @Published private(set) var axPermissionDenied: Bool = false

    /// Captures text and stores it as `pendingText`.  Returns the captured text (may be empty).
    @discardableResult
    func capture() -> String {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        axPermissionDenied = !trusted

        guard trusted else {
            pendingText = ""
            return ""
        }

        var text = grabSelectedTextViaAX() ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = grabSelectedTextViaTemporaryCopy() ?? ""
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = trimmed
        return trimmed
    }

    // MARK: - Private

    private func grabSelectedTextViaAX() -> String? {

        let sysEl = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            sysEl,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focusedVal = focusedRef,
            CFGetTypeID(focusedVal) == AXUIElementGetTypeID()
        else { return nil }

        let focused = focusedVal as! AXUIElement // swiftlint:disable:this force_cast

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success,
            let text = selectedRef as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return text
    }

    private func grabSelectedTextViaTemporaryCopy() -> String? {
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
        else { return nil }
        return text
    }

    private func simulateCopy() {
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
