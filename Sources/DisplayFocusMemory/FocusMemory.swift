import AppKit
import ApplicationServices

final class FocusMemory {
    private let settings: SettingsStore
    private let status: (String) -> Void
    private var rememberedWindowByDisplay: [CGDirectDisplayID: RememberedWindow] = [:]
    private var mouseMonitor: Any?
    private var focusTimer: Timer?
    private var pollTimer: Timer?
    private var permissionTimer: Timer?
    private var currentMouseDisplayID: CGDirectDisplayID?
    private var observers: [pid_t: AXObserver] = [:]
    private var observedApplicationPIDs: Set<pid_t> = []
    private var isDraggingWindow = false
    private var suppressRestoreUntil = Date.distantPast
    private var isRunning = false

    init(settings: SettingsStore, status: @escaping (String) -> Void) {
        self.settings = settings
        self.status = status
    }

    func start() {
        guard settings.isEnabled else {
            status("DisplayFocus Memory is disabled")
            return
        }

        guard AccessibilityPermission.request(prompt: true) else {
            status("Accessibility permission is required")
            installMouseMonitorIfNeeded()
            installPermissionPolling()
            return
        }

        guard !isRunning else { return }
        isRunning = true

        installMouseMonitorIfNeeded()
        permissionTimer?.invalidate()
        permissionTimer = nil
        initializeCurrentMouseDisplay()
        installFocusPolling()
        observeRunningApplications()
        rememberCurrentFocusedWindow()
        status("DisplayFocus Memory is running")
    }

    func pause() {
        stopTimers()
        isRunning = false
        status("DisplayFocus Memory is paused")
    }

    func stop() {
        stopTimers()

        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        observers.removeAll()
        observedApplicationPIDs.removeAll()
        isRunning = false
    }

    private func stopTimers() {
        focusTimer?.invalidate()
        focusTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] event in
            switch event.type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                self?.handleMouseMoved(isDrag: event.type != .mouseMoved)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                self?.handleMouseUp()
            default:
                break
            }
        }
    }

    private func installFocusPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.observeRunningApplications()
            self?.rememberCurrentFocusedWindow()
        }
    }

    private func initializeCurrentMouseDisplay() {
        currentMouseDisplayID = DisplayResolver.display(containing: currentMouseLocation())?.id
    }

    private func installPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, AccessibilityPermission.isTrusted() else { return }
            self.start()
        }
    }

    private func rememberAfterUserMouseAction(delay: TimeInterval = 0.08) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.rememberCurrentFocusedWindow()
        }
    }

    private func observeRunningApplications() {
        for application in NSWorkspace.shared.runningApplications {
            guard application.activationPolicy == .regular,
                  application.processIdentifier > 0,
                  !observedApplicationPIDs.contains(application.processIdentifier) else {
                continue
            }

            observeApplication(pid: application.processIdentifier)
        }
    }

    private func observeApplication(pid: pid_t) {
        var observer: AXObserver?
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = AXObserverCreate(pid, focusObserverCallback, &observer)

        guard result == .success, let observer else {
            return
        }

        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, context)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        observers[pid] = observer
        observedApplicationPIDs.insert(pid)
    }

    private func rememberCurrentFocusedWindow() {
        guard settings.isEnabled else {
            return
        }

        guard AccessibilityPermission.isTrusted() else {
            return
        }

        guard let remembered = AXWindowInspector.focusedWindow() else {
            return
        }

        guard AXWindowInspector.isRestorable(remembered, ignoredAppNames: settings.ignoredAppNames) else {
            return
        }

        guard let frame = AXWindowInspector.frame(of: remembered.window),
              let display = DisplayResolver.displayWithLargestOverlap(for: frame) else {
            return
        }

        let previous = rememberedWindowByDisplay[display.id]
        let memoryChanged = previous.map { !AXWindowInspector.isSameWindow($0, remembered) || $0.pid != remembered.pid } ?? true
        removeDuplicateMemory(for: remembered)
        rememberedWindowByDisplay[display.id] = remembered
        if memoryChanged {
            DebugLog.write("remember display=\(display.id) frontmost=\(AXWindowInspector.frontmostSummary()) \(AXWindowInspector.debugSummary(remembered)) memory=\(debugMemorySummary())")
        }
        status("Remembered \(remembered.appName) for display \(display.id)")
    }

    private func handleMouseMoved(isDrag: Bool) {
        guard settings.isEnabled, AccessibilityPermission.isTrusted() else {
            return
        }

        let location = currentMouseLocation()
        guard let display = DisplayResolver.display(containing: location) else {
            return
        }

        if isDrag {
            isDraggingWindow = true
            focusTimer?.invalidate()
            focusTimer = nil
            currentMouseDisplayID = display.id
            return
        }

        guard display.id != currentMouseDisplayID else {
            return
        }

        let previousMouseDisplayID = currentMouseDisplayID
        currentMouseDisplayID = display.id
        DebugLog.write("mouse crossed from=\(String(describing: previousMouseDisplayID)) to=\(display.id) frontmost=\(AXWindowInspector.frontmostSummary())")

        guard Date() >= suppressRestoreUntil else {
            DebugLog.write("restore suppressed until \(suppressRestoreUntil)")
            return
        }

        scheduleRestore(for: display)
    }

    private func handleMouseUp() {
        if isDraggingWindow {
            isDraggingWindow = false
            suppressRestoreUntil = Date().addingTimeInterval(0.4)
            currentMouseDisplayID = DisplayResolver.display(containing: currentMouseLocation())?.id
            rememberAfterUserMouseAction(delay: 0.15)
            return
        }

        rememberAfterUserMouseAction()
    }

    private func scheduleRestore(for display: PhysicalDisplay) {
        focusTimer?.invalidate()

        let delay = TimeInterval(settings.restoreDelayMilliseconds) / 1000
        DebugLog.write("scheduleRestore display=\(display.id) delay=\(settings.restoreDelayMilliseconds)ms")
        focusTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.restoreIfStillOnDisplay(display)
        }
    }

    private func restoreIfStillOnDisplay(_ display: PhysicalDisplay) {
        guard settings.isEnabled else {
            return
        }

        guard !settings.onlyRestoreOnExternalDisplays || !display.isBuiltin else {
            return
        }

        guard let currentDisplay = DisplayResolver.display(containing: currentMouseLocation()),
              currentDisplay.id == display.id else {
            return
        }

        guard let remembered = rememberedWindowByDisplay[display.id] else {
            return
        }

        guard AXWindowInspector.isRestorable(remembered, ignoredAppNames: settings.ignoredAppNames) else {
            DebugLog.write("restore skipped target not restorable display=\(display.id) \(AXWindowInspector.debugSummary(remembered))")
            return
        }

        let pids = debugRememberedPIDs(including: remembered)
        DebugLog.write("restore begin display=\(display.id) target=\(AXWindowInspector.debugSummary(remembered)) memory=\(debugMemorySummary())")
        DebugLog.snapshotWindowOrder(label: "before focusAndRaise display=\(display.id)", pids: pids)
        AXWindowInspector.focusAndRaise(remembered, snapshotPIDs: pids)
        DebugLog.snapshotWindowOrder(label: "after focusAndRaise display=\(display.id)", pids: pids)
        raiseRememberedWindowsOnOtherDisplays(except: display.id, restoredWindow: remembered)
        DebugLog.snapshotWindowOrder(label: "after other-display repair display=\(display.id)", pids: pids)
        scheduleDelayedWindowOrderSnapshots(displayID: display.id, pids: pids)
        status("Restored \(remembered.appName) on display \(display.id)")
    }

    private func raiseRememberedWindowsOnOtherDisplays(except displayID: CGDirectDisplayID, restoredWindow: RememberedWindow) {
        for (otherDisplayID, remembered) in rememberedWindowByDisplay where otherDisplayID != displayID {
            guard remembered.pid != restoredWindow.pid else {
                DebugLog.write("other-display skip same-pid display=\(otherDisplayID) restoredPID=\(restoredWindow.pid) \(AXWindowInspector.debugSummary(remembered))")
                continue
            }

            guard AXWindowInspector.isRestorable(remembered, ignoredAppNames: settings.ignoredAppNames) else {
                DebugLog.write("other-display skip not-restorable display=\(otherDisplayID) \(AXWindowInspector.debugSummary(remembered))")
                continue
            }

            guard let frame = AXWindowInspector.frame(of: remembered.window) else {
                DebugLog.write("other-display skip missing-frame display=\(otherDisplayID) \(AXWindowInspector.debugSummary(remembered))")
                continue
            }

            let resolvedDisplayID = DisplayResolver.displayWithLargestOverlap(for: frame)?.id
            guard resolvedDisplayID == otherDisplayID else {
                DebugLog.write("other-display skip display-mismatch expected=\(otherDisplayID) resolved=\(String(describing: resolvedDisplayID)) \(AXWindowInspector.debugSummary(remembered))")
                continue
            }

            DebugLog.write("other-display raise display=\(otherDisplayID) \(AXWindowInspector.debugSummary(remembered))")
            AXWindowInspector.raiseWithoutFocusing(remembered)
        }
    }

    private func removeDuplicateMemory(for remembered: RememberedWindow) {
        rememberedWindowByDisplay = rememberedWindowByDisplay.filter { _, existing in
            !AXWindowInspector.isSameWindow(existing, remembered)
        }
    }

    private func debugRememberedPIDs(including remembered: RememberedWindow? = nil) -> Set<pid_t> {
        var pids = Set(rememberedWindowByDisplay.values.map(\.pid))
        if let remembered {
            pids.insert(remembered.pid)
        }
        return pids
    }

    private func debugMemorySummary() -> String {
        rememberedWindowByDisplay
            .sorted { $0.key < $1.key }
            .map { displayID, remembered in
                "display=\(displayID):\(AXWindowInspector.debugSummary(remembered))"
            }
            .joined(separator: " || ")
    }

    private func scheduleDelayedWindowOrderSnapshots(displayID: CGDirectDisplayID, pids: Set<pid_t>) {
        guard DebugLog.isEnabled else { return }

        for delay in [0.05, 0.20, 0.50, 1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DebugLog.snapshotWindowOrder(label: "delayed +\(Int(delay * 1000))ms display=\(displayID)", pids: pids)
            }
        }
    }

    fileprivate func focusedWindowChanged(notification: String) {
        DebugLog.write("AX notification=\(notification) frontmost=\(AXWindowInspector.frontmostSummary())")
        rememberCurrentFocusedWindow()
    }

    private func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
    }

}

private let focusObserverCallback: AXObserverCallback = { _, _, notification, context in
    guard let context else { return }
    let memory = Unmanaged<FocusMemory>.fromOpaque(context).takeUnretainedValue()

    if notification as String == kAXFocusedWindowChangedNotification as String ||
        notification as String == kAXMainWindowChangedNotification as String {
        let notificationName = notification as String
        DispatchQueue.main.async {
            memory.focusedWindowChanged(notification: notificationName)
        }
    }
}
