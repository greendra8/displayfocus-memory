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

    static func focusAndRaise(_ remembered: RememberedWindow) {
        let app = NSRunningApplication(processIdentifier: remembered.pid)
        app?.activate(options: [.activateIgnoringOtherApps])

        AXUIElementSetAttributeValue(remembered.app, kAXFocusedWindowAttribute as CFString, remembered.window)
        AXUIElementSetAttributeValue(remembered.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(remembered.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(remembered.window, kAXRaiseAction as CFString)
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
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
