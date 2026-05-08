import Foundation

final class SettingsStore {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let delay = "restoreDelayMilliseconds"
        static let externalOnly = "onlyRestoreOnExternalDisplays"
        static let ignoredApps = "ignoredAppNames"
        static let startAtLoginRequested = "startAtLoginRequested"
    }

    var isEnabled: Bool
    var restoreDelayMilliseconds: Int
    var onlyRestoreOnExternalDisplays: Bool
    var ignoredAppNames: Set<String>
    var startAtLoginRequested: Bool

    init(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: Key.isEnabled) == nil {
            defaults.register(defaults: [
                Key.isEnabled: true,
                Key.delay: 125,
                Key.externalOnly: false,
                Key.ignoredApps: ["Dock", "SystemUIServer", "Notification Center", "Control Center"]
            ])
        }

        isEnabled = defaults.bool(forKey: Key.isEnabled)
        restoreDelayMilliseconds = defaults.integer(forKey: Key.delay)
        onlyRestoreOnExternalDisplays = defaults.bool(forKey: Key.externalOnly)
        ignoredAppNames = Set(defaults.stringArray(forKey: Key.ignoredApps) ?? [])
        startAtLoginRequested = defaults.bool(forKey: Key.startAtLoginRequested)

        if restoreDelayMilliseconds == 0 {
            restoreDelayMilliseconds = 125
        }
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Key.isEnabled)
        defaults.set(restoreDelayMilliseconds, forKey: Key.delay)
        defaults.set(onlyRestoreOnExternalDisplays, forKey: Key.externalOnly)
        defaults.set(Array(ignoredAppNames).sorted(), forKey: Key.ignoredApps)
        defaults.set(startAtLoginRequested, forKey: Key.startAtLoginRequested)
    }
}
