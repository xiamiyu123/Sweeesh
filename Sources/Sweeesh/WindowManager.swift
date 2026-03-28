import AppKit
import ApplicationServices

@MainActor
protocol WindowManaging {
    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws
}

@MainActor
struct WindowManager: WindowManaging {
    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws {
        DebugLog.info(DebugLog.windows, "Performing window action \(String(describing: action))")
        if action == .quitApplication {
            try quitFrontmostApplication()
            return
        }

        guard AXIsProcessTrusted() else {
            DebugLog.error(DebugLog.accessibility, "Accessibility permission missing before action \(String(describing: action))")
            throw WindowManagerError.accessibilityPermissionMissing
        }

        let app = try frontmostApplication()
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        switch action {
        case .minimize:
            let window = try focusedWindowElement(in: appElement)
            try setMinimized(true, for: window)
            return
        case .closeWindow:
            let window = try focusedWindowElement(in: appElement)
            try performAction("AXClose" as CFString, on: window)
            return
        case .cycleSameAppWindows:
            let currentWindow = try focusedWindowElement(in: appElement)
            try focusNextWindow(in: app, appElement: appElement, currentWindow: currentWindow)
            return
        case .leftHalf, .rightHalf, .maximize, .center:
            break
        case .quitApplication:
            return
        }

        let screens = NSScreen.screens
        let screenGeometry = ScreenGeometry(screenFrames: screens.map(\.frame))
        let focusedWindow = try focusedWindowElement(in: appElement)
        let currentFrame = screenGeometry.appKitFrame(
            fromAXFrame: try frame(of: focusedWindow)
        )
        let screenFrames = screens.map(\.visibleFrame)

        guard
            let currentScreenFrame = layoutEngine.screenContainingMost(
                of: currentFrame,
                in: screenFrames
            )
        else {
            throw WindowManagerError.unableToResolveScreen
        }

        let targetFrame = layoutEngine.targetFrame(
            for: action,
            currentWindowFrame: currentFrame,
            currentVisibleFrame: currentScreenFrame
        )

        DebugLog.debug(
            DebugLog.windows,
            "Calculated target frame \(NSStringFromRect(targetFrame)) from current frame \(NSStringFromRect(currentFrame))"
        )

        try setFrame(
            screenGeometry.axFrame(fromAppKitFrame: targetFrame),
            for: focusedWindow
        )
    }

    private func frontmostApplication() throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowManagerError.noFrontmostApplication
        }

        return app
    }

    func minimizeVisibleWindow(ofApplicationNamed applicationName: String) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(DebugLog.windows, "Attempting to minimize a visible window for \(applicationName)")

        let app = try runningApplication(named: applicationName)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = try windowElements(in: appElement).filter { !isMinimized($0) }
        DebugLog.debug(
            DebugLog.windows,
            "Visible window candidates for \(applicationName): [\(windowSummary(windows))]"
        )

        guard let targetWindow = windows.first else {
            DebugLog.debug(DebugLog.windows, "No visible window found to minimize for \(applicationName)")
            return false
        }

        try setMinimized(true, for: targetWindow)
        DebugLog.info(DebugLog.windows, "Minimized one visible window for \(applicationName)")
        return true
    }

    func restoreMinimizedWindow(ofApplicationNamed applicationName: String) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(DebugLog.windows, "Attempting to restore a minimized window for \(applicationName)")

        let app = try runningApplication(named: applicationName)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = try windowElements(in: appElement).filter { isMinimized($0) }
        DebugLog.debug(
            DebugLog.windows,
            "Minimized window candidates for \(applicationName): [\(windowSummary(windows))]"
        )

        guard let targetWindow = windows.first else {
            _ = app.activate(options: [.activateAllWindows])
            DebugLog.debug(DebugLog.windows, "No minimized window found for \(applicationName); activated app instead")
            return false
        }

        try setMinimized(false, for: targetWindow)
        try bringWindowToFront(targetWindow, for: app)
        DebugLog.info(DebugLog.windows, "Restored and raised one minimized window for \(applicationName)")
        return true
    }

    private func runningApplication(named applicationName: String) throws -> NSRunningApplication {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == applicationName }) {
            return app
        }

        DebugLog.error(DebugLog.windows, "Unable to find running application named \(applicationName)")
        throw WindowManagerError.noFrontmostApplication
    }

    private func focusedWindowElement(in appElement: AXUIElement) throws -> AXUIElement {
        var focusedWindowValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard error == .success, let focusedWindow = focusedWindowValue else {
            DebugLog.error(DebugLog.accessibility, "Failed to read focused window; AX error = \(error.rawValue)")
            throw WindowManagerError.noFocusedWindow
        }

        DebugLog.debug(DebugLog.windows, "Resolved focused window: \(windowSummary([unsafeDowncast(focusedWindow, to: AXUIElement.self)]))")
        return unsafeDowncast(focusedWindow, to: AXUIElement.self)
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        let position = try pointAttribute(kAXPositionAttribute as CFString, from: window)
        let size = try sizeAttribute(kAXSizeAttribute as CFString, from: window)
        return CGRect(origin: position, size: size).integral
    }

    private func setMinimized(_ minimized: Bool, for window: AXUIElement) throws {
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            window,
            kAXMinimizedAttribute as CFString,
            &settable
        )

        if settableError == .success, settable.boolValue {
            let value: CFTypeRef = minimized ? kCFBooleanTrue : kCFBooleanFalse
            let setError = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                value
            )
            guard setError == .success else {
                DebugLog.error(DebugLog.accessibility, "Setting AXMinimized=\(minimized) failed with error \(setError.rawValue) for window \(windowSummary([window]))")
                throw WindowManagerError.unableToPerformAction
            }
            DebugLog.debug(DebugLog.windows, "Set AXMinimized=\(minimized) for window \(windowSummary([window]))")
            return
        }

        if minimized, let minimizeButton = try? childElement(
            attribute: kAXMinimizeButtonAttribute as CFString,
            from: window
        ) {
            try performAction(kAXPressAction as CFString, on: minimizeButton)
            return
        }

        throw WindowManagerError.unableToPerformAction
    }

    private func focusNextWindow(
        in app: NSRunningApplication,
        appElement: AXUIElement,
        currentWindow: AXUIElement
    ) throws {
        let windows = try windowElements(in: appElement).filter { !isMinimized($0) }

        guard windows.count > 1 else {
            throw WindowManagerError.noAlternateWindow
        }

        let currentIndex = windows.firstIndex(where: { CFEqual($0, currentWindow) }) ?? 0
        let nextIndex = windows.index(after: currentIndex)
        let targetWindow = nextIndex == windows.endIndex ? windows[windows.startIndex] : windows[nextIndex]

        try bringWindowToFront(targetWindow, for: app)
    }

    private func quitFrontmostApplication() throws {
        let app = try frontmostApplication()
        guard app.terminate() else {
            throw WindowManagerError.unableToQuitApplication
        }
    }

    private func performAction(_ action: CFString, on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, action)
        guard error == .success else {
            DebugLog.error(DebugLog.accessibility, "AX action \(action as String) failed with error \(error.rawValue)")
            throw WindowManagerError.unableToPerformAction
        }
    }

    private func bringWindowToFront(_ window: AXUIElement, for app: NSRunningApplication) throws {
        DebugLog.debug(DebugLog.windows, "Bringing window to front for app \(app.localizedName ?? "unknown"): \(windowSummary([window]))")
        _ = app.activate(options: [.activateAllWindows])

        // Restored windows can take a moment to become orderable, so raise twice
        // around the focus attributes to make the behavior more reliable.
        try? performAction(kAXRaiseAction as CFString, on: window)
        try setBooleanAttribute(kAXMainAttribute as CFString, value: true, on: window)
        try setBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: window)
        try performAction(kAXRaiseAction as CFString, on: window)
        NSApp.activate(ignoringOtherApps: true)
        DebugLog.debug(DebugLog.windows, "Finished bring-to-front sequence for window \(windowSummary([window]))")
    }

    private func setBooleanAttribute(_ attribute: CFString, value: Bool, on element: AXUIElement) throws {
        let cfValue: CFTypeRef = value ? kCFBooleanTrue : kCFBooleanFalse
        let error = AXUIElementSetAttributeValue(element, attribute, cfValue)
        guard error == .success else {
            DebugLog.error(DebugLog.accessibility, "Failed to set AX bool attribute \(attribute as String) to \(value); error \(error.rawValue)")
            throw WindowManagerError.unableToPerformAction
        }
    }

    private func childElement(attribute: CFString, from element: AXUIElement) throws -> AXUIElement {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let child = value else {
            throw WindowManagerError.unableToPerformAction
        }

        return unsafeDowncast(child, to: AXUIElement.self)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) throws {
        var size = CGSize(width: max(1, frame.width), height: max(1, frame.height))
        var origin = CGPoint(x: frame.origin.x, y: frame.origin.y)

        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagerError.unableToSetFrame
        }

        guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowManagerError.unableToSetFrame
        }

        let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        guard sizeError == .success, positionError == .success else {
            DebugLog.error(
                DebugLog.accessibility,
                "Failed to set frame. Size error = \(sizeError.rawValue), position error = \(positionError.rawValue)"
            )
            throw WindowManagerError.unableToSetFrame
        }
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) throws -> CGPoint {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let axValue = value else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        let pointValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        var point = CGPoint.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point) else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) throws -> CGSize {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let axValue = value else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        let sizeValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(sizeValue) == .cgSize else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        return size
    }

    private func booleanAttribute(_ attribute: CFString, from element: AXUIElement) throws -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let cfValue = value else {
            throw WindowManagerError.unableToPerformAction
        }

        guard CFGetTypeID(cfValue) == CFBooleanGetTypeID() else {
            throw WindowManagerError.unableToPerformAction
        }

        return CFBooleanGetValue((cfValue as! CFBoolean))
    }

    private func windowElements(in appElement: AXUIElement) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        guard error == .success, let windows = value as? [AnyObject] else {
            DebugLog.error(DebugLog.accessibility, "Failed to enumerate windows; AX error = \(error.rawValue)")
            throw WindowManagerError.unableToEnumerateWindows
        }

        return windows.map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        (try? booleanAttribute(kAXMinimizedAttribute as CFString, from: window)) ?? false
    }

    private func windowSummary(_ windows: [AXUIElement]) -> String {
        windows.map { window in
            let title = (try? stringAttribute(kAXTitleAttribute as CFString, from: window)) ?? "<untitled>"
            let minimized = ((try? booleanAttribute(kAXMinimizedAttribute as CFString, from: window)) ?? false) ? "min" : "visible"
            let frameDescription: String
            if let frame = try? frame(of: window) {
                frameDescription = NSStringFromRect(frame)
            } else {
                frameDescription = "<unknown-frame>"
            }
            return "\"\(title)\"{\(minimized), frame=\(frameDescription)}"
        }
        .joined(separator: ", ")
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let stringValue = value as? String else {
            throw WindowManagerError.unableToPerformAction
        }

        return stringValue
    }
}

enum WindowManagerError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case noFocusedWindow
    case unableToReadWindowFrame
    case unableToSetFrame
    case unableToResolveScreen
    case unableToPerformAction
    case unableToQuitApplication
    case unableToEnumerateWindows
    case noAlternateWindow

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return L10n.string("error.permission_missing")
        case .noFrontmostApplication:
            return L10n.string("error.no_frontmost_app")
        case .noFocusedWindow:
            return L10n.string("error.no_focused_window")
        case .unableToReadWindowFrame:
            return L10n.string("error.read_window_frame_failed")
        case .unableToSetFrame:
            return L10n.string("error.set_window_frame_failed")
        case .unableToResolveScreen:
            return L10n.string("error.resolve_screen_failed")
        case .unableToPerformAction:
            return L10n.string("error.perform_action_failed")
        case .unableToQuitApplication:
            return L10n.string("error.quit_application_failed")
        case .unableToEnumerateWindows:
            return L10n.string("error.enumerate_windows_failed")
        case .noAlternateWindow:
            return L10n.string("error.no_alternate_window")
        }
    }
}
