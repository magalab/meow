import Foundation
@preconcurrency import ScreenCaptureKit

private struct SelectedRecordingContent: @unchecked Sendable {
    let filter: SCContentFilter?
}

@MainActor
public final class RecordingContentPickerController: NSObject, @preconcurrency SCContentSharingPickerObserver {
    private var continuation: CheckedContinuation<SelectedRecordingContent, Never>?

    public override init() {
        super.init()
    }

    public func selectMultipleWindows() async -> SCContentFilter? {
        guard continuation == nil else { return nil }
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.multipleWindows]
        configuration.allowsChangingSelectedContent = false
        if let bundleID = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleID]
        }
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        let selected = await withCheckedContinuation { continuation in
            self.continuation = continuation
            picker.present(using: .window)
        }
        return selected.filter
    }

    public func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        finish(nil, picker: picker)
    }

    public func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        finish(filter, picker: picker)
    }

    public func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(nil, picker: .shared)
    }

    private func finish(_ filter: SCContentFilter?, picker: SCContentSharingPicker) {
        picker.remove(self)
        picker.isActive = false
        continuation?.resume(returning: SelectedRecordingContent(filter: filter))
        continuation = nil
    }
}
