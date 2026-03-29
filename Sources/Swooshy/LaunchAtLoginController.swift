import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var isEnabled: Bool = false
    private(set) var statusMessage: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool, localize: (String) -> String) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refresh()
        } catch {
            refresh()
            statusMessage = localize("settings.launch_at_login.error")
            DebugLog.error(DebugLog.settings, "Failed to update launch-at-login state: \(error.localizedDescription)")
        }
    }

    func refresh(localize: ((String) -> String)? = nil) {
        isEnabled = SMAppService.mainApp.status == .enabled

        guard let localize else {
            statusMessage = nil
            return
        }

        switch SMAppService.mainApp.status {
        case .requiresApproval:
            statusMessage = localize("settings.launch_at_login.requires_approval")
        default:
            statusMessage = nil
        }
    }
}
