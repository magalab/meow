import Foundation
import ServiceManagement

final class AutoLaunchService {
    func apply(enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        let service = SMAppService.mainApp

        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("[Meow] Failed to update launch-at-login: \(error.localizedDescription)")
        }

        return isEnabled
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}
