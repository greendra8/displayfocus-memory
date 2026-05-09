import ApplicationServices
import AppKit

struct RememberedWindow {
    let app: AXUIElement
    let window: AXUIElement
    let pid: pid_t
    let appName: String
}

enum AXWindowInspector {
    static func focusedWindow() -> RememberedWindow? {
        // NSWorkspace matches the app name in the menu bar more reliably than
        // the system-wide AX focused application attribute on some apps.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let focused = focusedWindow(for: frontmost) {
            return focused
        }

        let system = AXUIElementCreateSystemWide()
        var focusedAppValue: AnyObject?

        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
              let focusedApp = focusedAppValue else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &pid)
        return focusedWindow(for: pid)
    }

    private static func focusedWindow(for app: NSRunningApplication) -> RememberedWindow? {
        focusedWindow(for: app.processIdentifier)
    }

    private static func focusedWindow(for pid: pid_t) -> RememberedWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowValue: AnyObject?

        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
              let focusedWindow = focusedWindowValue else {
            return nil
        }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let appName = runningApp?.localizedName ?? runningApp?.bundleIdentifier ?? "Unknown"

        return RememberedWindow(
            app: appElement,
            window: focusedWindow as! AXUIElement,
            pid: pid,
            appName: appName
        )
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = cgPointAttribute(window, kAXPositionAttribute),
              let size = cgSizeAttribute(window, kAXSizeAttribute) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    static func isRestorable(_ remembered: RememberedWindow, ignoredAppNames: Set<String>) -> Bool {
        guard !ignoredAppNames.contains(remembered.appName),
              let runningApp = NSRunningApplication(processIdentifier: remembered.pid),
              !runningApp.isHidden else {
            return false
        }

        guard let role = stringAttribute(remembered.window, kAXRoleAttribute),
              role == kAXWindowRole as String else {
            return false
        }

        if let subrole = stringAttribute(remembered.window, kAXSubroleAttribute),
           subrole != kAXStandardWindowSubrole as String {
            return false
        }

        if boolAttribute(remembered.window, kAXMinimizedAttribute) == true {
            return false
        }

        guard let frame = frame(of: remembered.window),
              frame.width > 20,
              frame.height > 20,
              DisplayResolver.displayWithLargestOverlap(for: frame) != nil,
              isOnCurrentVisibleSpace(pid: remembered.pid, frame: frame) else {
            return false
        }

        return true
    }

    static func shouldSkipAutomaticRestore(_ remembered: RememberedWindow) -> Bool {
        hasFullscreenAuxiliaryWindow(onSameDisplayAs: remembered)
    }

    static func focusAndRaise(_ remembered: RememberedWindow, snapshotPIDs: Set<pid_t> = []) {
        DebugLog.write("focusAndRaise begin frontmost=\(frontmostSummary()) \(debugSummary(remembered))")

        let focusedWindowResult = AXUIElementSetAttributeValue(remembered.app, kAXFocusedWindowAttribute as CFString, remembered.window)
        DebugLog.write("focusAndRaise set focusedWindow result=\(focusedWindowResult) frontmost=\(frontmostSummary()) \(debugSummary(remembered))")
        snapshotWindowOrder(label: "after set focusedWindow \(remembered.appName)", pids: snapshotPIDs)

        let mainResult = AXUIElementSetAttributeValue(remembered.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        DebugLog.write("focusAndRaise set main result=\(mainResult) frontmost=\(frontmostSummary()) \(debugSummary(remembered))")
        snapshotWindowOrder(label: "after set main \(remembered.appName)", pids: snapshotPIDs)

        let focusedResult = AXUIElementSetAttributeValue(remembered.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        DebugLog.write("focusAndRaise set focused result=\(focusedResult) frontmost=\(frontmostSummary()) \(debugSummary(remembered))")
        snapshotWindowOrder(label: "after set focused \(remembered.appName)", pids: snapshotPIDs)

        let raiseResult = AXUIElementPerformAction(remembered.window, kAXRaiseAction as CFString)
        DebugLog.write("focusAndRaise raise result=\(raiseResult) frontmost=\(frontmostSummary()) \(debugSummary(remembered))")
        snapshotWindowOrder(label: "after target raise \(remembered.appName)", pids: snapshotPIDs)

        let app = NSRunningApplication(processIdentifier: remembered.pid)
        let didActivate = app?.activate(options: [.activateIgnoringOtherApps]) ?? false
        DebugLog.write("focusAndRaise activate result=\(didActivate) frontmost=\(frontmostSummary()) \(debugSummary(remembered))")
        snapshotWindowOrder(label: "after activate \(remembered.appName)", pids: snapshotPIDs)
    }

    static func raiseWithoutFocusing(_ remembered: RememberedWindow) {
        DebugLog.write("raiseWithoutFocusing begin \(debugSummary(remembered))")
        let raiseResult = AXUIElementPerformAction(remembered.window, kAXRaiseAction as CFString)
        DebugLog.write("raiseWithoutFocusing result=\(raiseResult) \(debugSummary(remembered))")
    }

    static func isSameWindow(_ lhs: RememberedWindow, _ rhs: RememberedWindow) -> Bool {
        CFEqual(lhs.window, rhs.window)
    }

    static func debugSummary(_ remembered: RememberedWindow) -> String {
        let title = stringAttribute(remembered.window, kAXTitleAttribute) ?? "untitled"
        let role = stringAttribute(remembered.window, kAXRoleAttribute) ?? "unknown-role"
        let subrole = stringAttribute(remembered.window, kAXSubroleAttribute) ?? "unknown-subrole"
        let windowNumber = intAttribute(remembered.window, "AXWindowNumber").map(String.init) ?? "unknown-window-number"
        let frameDescription = frame(of: remembered.window).map(rectDescription) ?? "unknown-frame"

        return "app='\(remembered.appName)' pid=\(remembered.pid) axHash=\(CFHash(remembered.window)) axWindowNumber=\(windowNumber) role=\(role) subrole=\(subrole) frame=\(frameDescription) title='\(title)'"
    }

    static func frontmostSummary() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return "unknown"
        }

        let name = app.localizedName ?? app.bundleIdentifier ?? "unknown"
        return "\(name)(pid=\(app.processIdentifier))"
    }

    private static func snapshotWindowOrder(label: String, pids: Set<pid_t>) {
        guard !pids.isEmpty else { return }
        DebugLog.snapshotWindowOrder(label: label, pids: pids)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Int ?? (value as? NSNumber)?.intValue
    }

    private static func hasFullscreenAuxiliaryWindow(onSameDisplayAs remembered: RememberedWindow) -> Bool {
        guard let targetFrame = frame(of: remembered.window),
              let targetDisplayID = DisplayResolver.displayWithLargestOverlap(for: targetFrame)?.id else {
            return false
        }

        let appElement = AXUIElementCreateApplication(remembered.pid)
        var windowsValue: AnyObject?

        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return false
        }

        return windows.contains { window in
            guard boolAttribute(window, "AXFullScreen") == true,
                  stringAttribute(window, kAXRoleAttribute) == kAXWindowRole as String,
                  stringAttribute(window, kAXSubroleAttribute) != kAXStandardWindowSubrole as String,
                  let fullscreenFrame = frame(of: window),
                  let fullscreenDisplayID = DisplayResolver.displayWithLargestOverlap(for: fullscreenFrame)?.id else {
                return false
            }

            return fullscreenDisplayID == targetDisplayID
        }
    }

    private static func cgPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func cgSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func isOnCurrentVisibleSpace(pid: pid_t, frame: CGRect) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else {
                return false
            }

            var cgFrame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &cgFrame) else {
                return false
            }

            return cgFrame.intersection(frame).area > 100
        }
    }

    private static func rectDescription(_ rect: CGRect) -> String {
        "x=\(Int(rect.origin.x)),y=\(Int(rect.origin.y)),w=\(Int(rect.width)),h=\(Int(rect.height))"
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
