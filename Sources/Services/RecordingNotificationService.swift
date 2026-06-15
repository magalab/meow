import Foundation
import UserNotifications

final class RecordingNotificationService: @unchecked Sendable {
    func requestAuthorization() {
        guard Self.canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCompleted(_ artifact: RecordingArtifact) {
        guard Self.canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.recordingNotificationTitle
        content.body = String(
            format: L10n.recordingNotificationBody,
            artifact.fileURL.lastPathComponent
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "recording-\(artifact.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
