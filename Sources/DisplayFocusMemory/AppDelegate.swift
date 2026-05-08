import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = SettingsStore()
    private lazy var focusMemory = FocusMemory(settings: settings) { [weak self] status in
        self?.updateStatus(status)
    }

    private var lastStatus = "Starting"

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        rebuildMenu()
        focusMemory.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusMemory.stop()
    }

    private func configureStatusItem() {
        statusItem.button?.title = "DFM"
        statusItem.button?.toolTip = "DisplayFocus Memory"
        statusItem.menu = NSMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusItemText = NSMenuItem(title: "DisplayFocus Memory", action: nil, keyEquivalent: "")
        statusItemText.isEnabled = false
        menu.addItem(statusItemText)

        let currentStatus = NSMenuItem(title: lastStatus, action: nil, keyEquivalent: "")
        currentStatus.isEnabled = false
        menu.addItem(currentStatus)

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let delayItem = NSMenuItem(title: "Restore Delay: \(settings.restoreDelayMilliseconds) ms", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu()
        menu.addItem(delayItem)

        let externalOnlyItem = NSMenuItem(title: "Only Restore on External Displays", action: #selector(toggleExternalOnly), keyEquivalent: "")
        externalOnlyItem.target = self
        externalOnlyItem.state = settings.onlyRestoreOnExternalDisplays ? .on : .off
        menu.addItem(externalOnlyItem)

        let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startAtLoginItem.target = self
        startAtLoginItem.state = settings.startAtLoginRequested ? .on : .off
        menu.addItem(startAtLoginItem)

        menu.addItem(.separator())

        let ignored = NSMenuItem(title: "Ignored Apps", action: nil, keyEquivalent: "")
        ignored.submenu = ignoredAppsMenu()
        menu.addItem(ignored)

        let permission = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func delayMenu() -> NSMenu {
        let menu = NSMenu()
        for delay in [75, 100, 125, 150, 200, 300] {
            let item = NSMenuItem(title: "\(delay) ms", action: #selector(setDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = delay
            item.state = settings.restoreDelayMilliseconds == delay ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func ignoredAppsMenu() -> NSMenu {
        let menu = NSMenu()
        let knownApps = ["Dock", "Finder", "SystemUIServer", "Notification Center", "Control Center"]

        for appName in knownApps {
            let item = NSMenuItem(title: appName, action: #selector(toggleIgnoredApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appName
            item.state = settings.ignoredAppNames.contains(appName) ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func updateStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            guard self?.lastStatus != status else { return }
            self?.lastStatus = status
            self?.statusItem.button?.toolTip = status
            self?.rebuildMenu()
        }
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        settings.save()
        settings.isEnabled ? focusMemory.start() : focusMemory.pause()
        rebuildMenu()
    }

    @objc private func toggleExternalOnly() {
        settings.onlyRestoreOnExternalDisplays.toggle()
        settings.save()
        rebuildMenu()
    }

    @objc private func toggleStartAtLogin() {
        settings.startAtLoginRequested.toggle()
        settings.save()
        let result = LoginItemController.setEnabled(settings.startAtLoginRequested)
        updateStatus(result)
        rebuildMenu()
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        guard let delay = sender.representedObject as? Int else { return }
        settings.restoreDelayMilliseconds = delay
        settings.save()
        rebuildMenu()
    }

    @objc private func toggleIgnoredApp(_ sender: NSMenuItem) {
        guard let appName = sender.representedObject as? String else { return }
        if settings.ignoredAppNames.contains(appName) {
            settings.ignoredAppNames.remove(appName)
        } else {
            settings.ignoredAppNames.insert(appName)
        }
        settings.save()
        rebuildMenu()
    }

    @objc private func requestAccessibilityPermission() {
        if AccessibilityPermission.request(prompt: true) {
            updateStatus("Accessibility permission granted")
            focusMemory.start()
        } else {
            updateStatus("Waiting for Accessibility permission")
        }
    }
}
