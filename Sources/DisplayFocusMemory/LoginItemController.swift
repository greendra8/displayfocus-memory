import Foundation
import ServiceManagement

enum LoginItemController {
    static func setEnabled(_ enabled: Bool) -> String {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return "Start at Login requires running from the built .app bundle"
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
                return "Start at Login enabled"
            } else {
                try SMAppService.mainApp.unregister()
                return "Start at Login disabled"
            }
        } catch {
            return "Could not update Start at Login: \(error.localizedDescription)"
        }
    }
}
