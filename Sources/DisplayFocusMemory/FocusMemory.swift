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

        removeDuplicateMemory(for: remembered)
        rememberedWindowByDisplay[display.id] = remembered
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

        currentMouseDisplayID = display.id

        guard Date() >= suppressRestoreUntil else {
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
            return
        }

        AXWindowInspector.focusAndRaise(remembered)
        raiseRememberedWindowsOnOtherDisplays(except: display.id)
        status("Restored \(remembered.appName) on display \(display.id)")
    }

    private func raiseRememberedWindowsOnOtherDisplays(except displayID: CGDirectDisplayID) {
        for (otherDisplayID, remembered) in rememberedWindowByDisplay where otherDisplayID != displayID {
            guard AXWindowInspector.isRestorable(remembered, ignoredAppNames: settings.ignoredAppNames),
                  let frame = AXWindowInspector.frame(of: remembered.window),
                  DisplayResolver.displayWithLargestOverlap(for: frame)?.id == otherDisplayID else {
                continue
            }

            AXWindowInspector.raiseWithoutFocusing(remembered)
        }
    }

    private func removeDuplicateMemory(for remembered: RememberedWindow) {
        rememberedWindowByDisplay = rememberedWindowByDisplay.filter { _, existing in
            !AXWindowInspector.isSameWindow(existing, remembered)
        }
    }

    fileprivate func focusedWindowChanged() {
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
        DispatchQueue.main.async {
            memory.focusedWindowChanged()
        }
    }
}
