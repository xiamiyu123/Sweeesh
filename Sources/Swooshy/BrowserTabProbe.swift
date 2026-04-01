import AppKit
import ApplicationServices
import CoreGraphics

/// Detects whether the pointer is hovering over a supported app tab and can
/// simulate a middle-click to close that specific tab without switching to it first.
///
/// Supported apps include major browsers plus VS Code-based editors such as
/// Visual Studio Code, Cursor, Windsurf, Trae, and Antigravity.
/// When the pointer is not over a tab, the caller should fall back to the
/// normal close-window or quit-application action.
@MainActor
enum BrowserTabProbe {
    enum TabHostFamily {
        case webKit
        case generic
    }

    struct TabAncestryNode: Equatable {
        let role: String
        let subrole: String
        let title: String
        let matchedTabElement: Bool
    }

    private struct CachedHostSupport {
        let isSupported: Bool
        let description: String
        let family: TabHostFamily
    }

    // MARK: - Public API

    /// Returns `true` if the element at `appKitPoint` belongs to a supported tab host
    /// and appears to be a tab UI element.
    static func isBrowserTab(
        at appKitPoint: CGPoint,
        processIdentifier: pid_t
    ) -> Bool {
        guard
            let hostSupport = hostSupport(processIdentifier: processIdentifier),
            hostSupport.isSupported
        else {
            DebugLog.debug(
                DebugLog.dock,
                "BrowserTabProbe skipped unsupported tab host pid=\(processIdentifier) at \(NSStringFromPoint(appKitPoint))"
            )
            return false
        }

        let isTab = axElementIsTab(
            at: appKitPoint,
            hostFamily: hostSupport.family
        )
        DebugLog.debug(
            DebugLog.dock,
            "BrowserTabProbe result pid=\(processIdentifier) host=\(hostSupport.description) point=\(NSStringFromPoint(appKitPoint)) => \(isTab ? "tab" : "not-tab")"
        )
        return isTab
    }

    /// Sends a synthetic middle-click (button 3) at the given AppKit coordinate.
    /// This closes the tab under the pointer in every major browser.
    @discardableResult
    static func simulateMiddleClick(at appKitPoint: CGPoint) -> Bool {
        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        let cgPoint = geometry.axPoint(fromAppKitPoint: appKitPoint)

        guard
            let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .center
            ),
            let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .center
            )
        else {
            DebugLog.error(DebugLog.dock, "Failed to create CGEvent for middle-click at \(NSStringFromPoint(appKitPoint))")
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)

        DebugLog.info(
            DebugLog.dock,
            "Simulated middle-click at CG point \(NSStringFromPoint(cgPoint)) (AppKit \(NSStringFromPoint(appKitPoint)))"
        )

        return true
    }

    /// Sends a synthetic middle-click at the current mouse location.
    @discardableResult
    static func simulateMiddleClickAtMouseLocation() -> Bool {
        simulateMiddleClick(at: NSEvent.mouseLocation)
    }

    // MARK: - Supported App Identification

    private static let knownBrowserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "company.thebrowser.Browser",       // Arc
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.kagi.kagimacOS",               // Orion
        "org.chromium.Chromium",
        "com.nickvision.nickelchrome",       // Nickel
    ]

    private static let webKitBrowserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.kagi.kagimacOS",               // Orion
    ]

    private static let knownEditorBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "org.vscodium",
        "com.google.antigravity",
    ]

    private static let knownEditorNames: Set<String> = [
        "visual studio code",
        "visual studio code - insiders",
        "vscodium",
        "code - oss",
        "cursor",
        "windsurf",
        "trae",
        "antigravity",
        "void",
        "pearai",
        "kiro",
    ]

    /// Cache resolved host support per PID to avoid repeated lookups.
    private static var hostSupportCache: [pid_t: CachedHostSupport] = [:]

    static func supportsTabCloseHost(bundleIdentifier: String?, localizedName: String?) -> Bool {
        if let bundleIdentifier, knownBrowserBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if let bundleIdentifier, knownEditorBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        guard
            let localizedName = localizedName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            localizedName.isEmpty == false
        else {
            return false
        }

        return knownEditorNames.contains(localizedName)
    }

    private static func hostSupport(processIdentifier: pid_t) -> CachedHostSupport? {
        if let cached = hostSupportCache[processIdentifier] {
            return cached
        }

        guard let app = NSRunningApplication(processIdentifier: processIdentifier) else {
            return nil
        }

        let isSupported = supportsTabCloseHost(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName
        )
        let description = [app.localizedName, app.bundleIdentifier]
            .compactMap { $0 }
            .joined(separator: " / ")
        let support = CachedHostSupport(
            isSupported: isSupported,
            description: description.isEmpty ? "<unknown>" : description,
            family: tabHostFamily(bundleIdentifier: app.bundleIdentifier)
        )
        hostSupportCache[processIdentifier] = support
        return support
    }

    private static func tabHostFamily(bundleIdentifier: String?) -> TabHostFamily {
        guard let bundleIdentifier else {
            return .generic
        }

        if webKitBrowserBundleIdentifiers.contains(bundleIdentifier) {
            return .webKit
        }

        return .generic
    }

    // MARK: - AX Tab Detection

    /// Known AX roles and subroles that indicate a tab element in various browsers.
    private static let tabRoles: Set<String> = [
        "AXTab",           // Chrome, Chromium-based
        "AXRadioButton",   // Safari (with AXTabButton subrole)
    ]

    private static let tabSubroles: Set<String> = [
        "AXTabButton",  // Safari
    ]

    private static let browserChromeContainerRoles: Set<String> = [
        "AXToolbar",
        "AXTabGroup",
    ]

    private static let pageContentRoles: Set<String> = [
        "AXWebArea",
        "AXDocument",
        "AXDocumentArticle",
    ]

    private static let pageContentSubroles: Set<String> = [
        "AXTabPanel",
    ]

    /// Walks upward from the deepest hit element to check if it (or any ancestor
    /// up to a small depth) has a tab-related AX role.
    private static func axElementIsTab(
        at appKitPoint: CGPoint,
        hostFamily: TabHostFamily
    ) -> Bool {
        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        let axPoint = geometry.axPoint(fromAppKitPoint: appKitPoint)

        let systemWideElement = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(axPoint.x),
            Float(axPoint.y),
            &hitElement
        )

        guard result == .success, let element = hitElement else {
            DebugLog.debug(
                DebugLog.dock,
                "BrowserTabProbe hit-test failed at AX point \(NSStringFromPoint(axPoint)) (AppKit \(NSStringFromPoint(appKitPoint))), result=\(result.rawValue)"
            )
            return false
        }

        // Walk the element and its ancestors, then validate the full ancestry so
        // page-level ARIA tab widgets do not masquerade as browser chrome tabs.
        var current: AXUIElement? = element
        let maxDepth = 10
        var ancestry: [TabAncestryNode] = []

        for _ in 0..<maxDepth {
            guard let node = current else { break }

            let role = stringAttribute(kAXRoleAttribute as CFString, from: node) ?? "<nil>"
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: node) ?? "<nil>"
            let title = stringAttribute(kAXTitleAttribute as CFString, from: node) ?? "<nil>"
            let matchedTabElement = isTabElement(node, at: axPoint)
            ancestry.append(
                TabAncestryNode(
                    role: role,
                    subrole: subrole,
                    title: title,
                    matchedTabElement: matchedTabElement
                )
            )

            // Walk to parent.
            var parentRef: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(
                node,
                kAXParentAttribute as CFString,
                &parentRef
            )

            guard parentResult == .success, let parent = parentRef else {
                return logAndReturnAncestryVerdict(
                    ancestry,
                    hostFamily: hostFamily,
                    axPoint: axPoint,
                    appKitPoint: appKitPoint,
                    interruptionReason: "stopped parent walk (result=\(parentResult.rawValue))"
                )
            }

            guard CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return logAndReturnAncestryVerdict(
                    ancestry,
                    hostFamily: hostFamily,
                    axPoint: axPoint,
                    appKitPoint: appKitPoint,
                    interruptionReason: "stopped parent walk due non-AX parent"
                )
            }

            current = unsafeDowncast(parent, to: AXUIElement.self)
        }

        return logAndReturnAncestryVerdict(
            ancestry,
            hostFamily: hostFamily,
            axPoint: axPoint,
            appKitPoint: appKitPoint
        )
    }

    static func acceptsMatchedTabAncestry(
        _ ancestry: [TabAncestryNode],
        hostFamily: TabHostFamily
    ) -> Bool {
        guard ancestry.contains(where: \.matchedTabElement) else {
            return false
        }

        if ancestry.contains(where: isPageContentMarker) {
            return false
        }

        let matchedRadioTabButton = ancestry.contains {
            $0.matchedTabElement &&
                $0.role == "AXRadioButton" &&
                tabSubroles.contains($0.subrole)
        }

        guard matchedRadioTabButton else {
            return true
        }

        if hostFamily == .webKit {
            return true
        }

        return ancestry.contains { browserChromeContainerRoles.contains($0.role) }
    }

    private static func logAndReturnAncestryVerdict(
        _ ancestry: [TabAncestryNode],
        hostFamily: TabHostFamily,
        axPoint: CGPoint,
        appKitPoint: CGPoint,
        interruptionReason: String? = nil
    ) -> Bool {
        let ancestrySummary = formattedAncestry(ancestry)

        if ancestry.contains(where: \.matchedTabElement) {
            let isAccepted = acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: hostFamily
            )
            let interruptionSuffix = interruptionReason.map { " after \($0)" } ?? ""
            DebugLog.debug(
                DebugLog.dock,
                "BrowserTabProbe \(isAccepted ? "matched" : "rejected") tab ancestry at AX point \(NSStringFromPoint(axPoint))\(interruptionSuffix): [\(ancestrySummary)]"
            )
            return isAccepted
        }

        let interruptionPrefix = interruptionReason.map { "\($0); " } ?? ""
        DebugLog.debug(
            DebugLog.dock,
            "BrowserTabProbe \(interruptionPrefix)no tab match at AX point \(NSStringFromPoint(axPoint)) (AppKit \(NSStringFromPoint(appKitPoint))); ancestry [\(ancestrySummary)]"
        )
        return false
    }

    private static func formattedAncestry(_ ancestry: [TabAncestryNode]) -> String {
        ancestry.enumerated()
            .map { depth, node in
                let matchedPrefix = node.matchedTabElement ? "*" : ""
                return "d\(depth):\(matchedPrefix)\(node.role)/\(node.subrole)/\(node.title)"
            }
            .joined(separator: " -> ")
    }

    private static func isPageContentMarker(_ node: TabAncestryNode) -> Bool {
        if pageContentRoles.contains(node.role) {
            return true
        }

        if pageContentSubroles.contains(node.subrole) {
            return true
        }

        return node.subrole.hasPrefix("AXLandmark")
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else {
            return nil
        }

        return valueRef as? String
    }

    private static func isTabElement(_ element: AXUIElement, at axPoint: CGPoint) -> Bool {
        // Read AXRole.
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        )

        guard roleResult == .success, let role = roleRef as? String else {
            return false
        }

        // Chromium may expose a top-level AXTabGroup for the full strip, so we
        // only treat it as a tab hit when a point-contained child looks like a tab.
        if role == "AXTabGroup" {
            return tabGroupContainsTab(at: axPoint, within: element)
        }

        // Direct tab role match (Chrome, Chromium-based).
        if tabRoles.contains(role) {
            // For AXRadioButton, further verify the subrole is AXTabButton (Safari).
            if role == "AXRadioButton" {
                return subroleMatches(element)
            }
            return true
        }

        // Some browsers expose tab groups; check subrole on other roles too.
        return subroleMatches(element)
    }

    private static func tabGroupContainsTab(at axPoint: CGPoint, within tabGroup: AXUIElement) -> Bool {
        var queue: [(AXUIElement, Int)] = [(tabGroup, 0)]
        let maxDepth = 3

        while queue.isEmpty == false {
            let (node, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }

            for child in childElements(of: node) {
                if let frame = frameAttribute(from: child), frame.contains(axPoint) == false {
                    continue
                }

                let role = stringAttribute(kAXRoleAttribute as CFString, from: child) ?? ""
                let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: child) ?? ""
                let title = stringAttribute(kAXTitleAttribute as CFString, from: child) ?? ""

                if role == "AXTab" {
                    return true
                }

                if role == "AXRadioButton", tabSubroles.contains(subrole) {
                    return true
                }

                if tabSubroles.contains(subrole) {
                    return true
                }

                // Chromium fallback: tabs can appear as AXGroup with title + press action.
                if role == "AXGroup", title.isEmpty == false, supportsPressAction(child) {
                    return true
                }

                queue.append((child, depth + 1))
            }
        }

        return false
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )

        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return []
        }

        return children
    }

    private static func frameAttribute(from element: AXUIElement) -> CGRect? {
        var frameRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXFrame" as CFString,
            &frameRef
        )

        guard result == .success, let frameRef else {
            return nil
        }

        guard CFGetTypeID(frameRef) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(frameRef, to: AXValue.self)

        var frame = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &frame) else {
            return nil
        }

        return frame
    }

    private static func supportsPressAction(_ element: AXUIElement) -> Bool {
        var actionNamesRef: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNamesRef)
        guard result == .success, let actions = actionNamesRef as? [String] else {
            return false
        }

        return actions.contains("AXPress")
    }

    private static func subroleMatches(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleRef
        )

        guard subroleResult == .success, let subrole = subroleRef as? String else {
            return false
        }

        return tabSubroles.contains(subrole)
    }

    // MARK: - Cache Maintenance

    static func clearCache() {
        hostSupportCache.removeAll()
    }
}
