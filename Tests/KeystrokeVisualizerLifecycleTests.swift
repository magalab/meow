import AppKit
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Suite("Keystroke visualizer lifecycle")
@MainActor
struct KeystrokeVisualizerLifecycleTests {
    @Test
    func repeatedEnableAndStopManageOneEventTap() {
        var starts = 0
        var stops = 0
        let driver = KeystrokeVisualizerService.EventTapDriver(
            start: { _ in
                starts += 1
                return NSObject()
            },
            stop: { _ in stops += 1 },
            reenable: { _ in }
        )
        let service = KeystrokeVisualizerService(
            eventTapDriver: driver,
            permissionChecker: { _ in true }
        )
        var settings = AppSettings.default
        settings.keystrokeVisualizerEnabled = true

        service.apply(settings: settings)
        service.apply(settings: settings)

        #expect(starts == 1)
        #expect(service.permissionState == .trusted)

        service.stop()
        service.stop()
        #expect(stops == 1)

        service.apply(settings: settings)
        #expect(starts == 2)
        service.stop()
        #expect(stops == 2)
    }

    @Test
    func permissionRecoveryStartsTapAfterGrant() {
        let permission = PermissionFixture()
        var starts = 0
        var stops = 0
        let driver = KeystrokeVisualizerService.EventTapDriver(
            start: { _ in
                starts += 1
                return NSObject()
            },
            stop: { _ in stops += 1 },
            reenable: { _ in }
        )
        let service = KeystrokeVisualizerService(
            eventTapDriver: driver,
            permissionChecker: { _ in permission.isGranted }
        )
        var settings = AppSettings.default
        settings.keystrokeVisualizerEnabled = true

        service.apply(settings: settings)
        #expect(service.permissionState == .denied)
        #expect(starts == 0)

        permission.isGranted = true
        service.retryAfterPermissionChange()

        #expect(service.permissionState == .trusted)
        #expect(starts == 1)
        service.stop()
        #expect(stops == 1)
    }

    @Test
    func permissionRevocationStopsTapAndGrantRestartsIt() {
        let permission = PermissionFixture()
        permission.isGranted = true
        var starts = 0
        var stops = 0
        let driver = KeystrokeVisualizerService.EventTapDriver(
            start: { _ in
                starts += 1
                return NSObject()
            },
            stop: { _ in stops += 1 },
            reenable: { _ in }
        )
        let service = KeystrokeVisualizerService(
            eventTapDriver: driver,
            permissionChecker: { _ in permission.isGranted }
        )
        var settings = AppSettings.default
        settings.keystrokeVisualizerEnabled = true

        service.apply(settings: settings)
        #expect(starts == 1)
        #expect(service.permissionState == .trusted)

        permission.isGranted = false
        service.retryAfterPermissionChange()
        #expect(service.permissionState == .denied)
        #expect(stops == 1)

        service.retryAfterPermissionChange()
        #expect(starts == 1)
        #expect(stops == 1)

        permission.isGranted = true
        service.retryAfterPermissionChange()
        #expect(service.permissionState == .trusted)
        #expect(starts == 2)
        #expect(stops == 1)

        service.stop()
        #expect(stops == 2)
    }

    @MainActor
    private final class PermissionFixture {
        var isGranted = false
    }
}
