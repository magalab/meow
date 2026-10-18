import AppKit
import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
@Test("Dock icon calendar observer installs once and stops cleanly")
func dockIconCalendarObserverLifecycle() async {
    let notificationCenter = NotificationCenter()
    var refreshCount = 0
    let service = DockIconService(
        notificationCenter: notificationCenter,
        refreshAction: { _ in refreshCount += 1 }
    )

    service.start(style: .default)
    service.start(style: .default)
    let startRefreshCount = refreshCount
    notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
    for _ in 0..<10 { await Task.yield() }
    #expect(refreshCount == startRefreshCount + 1)

    service.stop()
    service.stop()
    notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
    for _ in 0..<10 { await Task.yield() }
    #expect(refreshCount == startRefreshCount + 1)
}
