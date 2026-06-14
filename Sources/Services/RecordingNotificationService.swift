import Foundation
import UserNotifications

final class RecordingNotificationService: @unchecked Sendable {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCompleted(_ artifact: RecordingArtifact) {
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
}
