import AppKit
import ApplicationServices
import Foundation

struct AppIdentity: Sendable {
    let bundleURL: URL
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let localizedName: String

    init?(
        bundleURL: URL?,
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        localizedName: String?
    ) {
        guard let bundleURL else {
            return nil
        }

        self.bundleURL = Self.canonicalBundleURL(from: bundleURL)
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName?.isEmpty == false
            ? localizedName ?? "Application"
            : Self.canonicalBundleURL(from: bundleURL).deletingPathExtension().lastPathComponent
    }

    init?(application: NSRunningApplication) {
        self.init(
            bundleURL: application.bundleURL,
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            localizedName: application.localizedName
        )
    }

    var logDescription: String {
        if let bundleIdentifier, bundleIdentifier.isEmpty == false {
            return "\(localizedName) [\(bundleIdentifier)]"
        }

        return localizedName
    }

    func matches(_ application: NSRunningApplication) -> Bool {
        guard let other = AppIdentity(application: application) else {
            return false
        }

        return self == other
    }

    static func canonicalBundleURL(from bundleURL: URL) -> URL {
        let standardizedURL = bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL

        if standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            return standardizedURL
        }

        var currentURL = standardizedURL
        while currentURL.path != "/" {
            if currentURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL == currentURL {
                break
            }
            currentURL = parentURL
        }

        return standardizedURL
    }
}

extension AppIdentity: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleURL == rhs.bundleURL &&
            lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleURL)
        hasher.combine(bundleIdentifier)
    }
}

struct WindowIdentity: Hashable, Sendable {
    private let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct DockItemHandle: Hashable, Sendable {
    private let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct DockMinimizedItemHandle: Hashable, Sendable {
    private let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct DockElementToken: Hashable, Sendable {
    let processIdentifier: pid_t
    let rawHash: Int

    init(element: AXUIElement) {
        processIdentifier = AXAttributeReader.processIdentifier(of: element) ?? 0
        rawHash = Int(CFHash(element as CFTypeRef))
    }

    init(processIdentifier: pid_t = 0, rawHash: Int) {
        self.processIdentifier = processIdentifier
        self.rawHash = rawHash
    }
}

enum InteractionSource: Equatable, Sendable {
    case dockAppItem(DockItemHandle)
    case dockMinimizedItem(DockMinimizedItemHandle)
    case titleBar
    case browserTabFallback
}

enum InteractionTarget: Equatable, Sendable {
    case application(AppIdentity, source: InteractionSource)
    case window(WindowIdentity, app: AppIdentity, source: InteractionSource)
    case unresolvedDockMinimizedItem(DockMinimizedItemHandle)

    var appIdentity: AppIdentity? {
        switch self {
        case .application(let app, _), .window(_, let app, _):
            return app
        case .unresolvedDockMinimizedItem:
            return nil
        }
    }

    var source: InteractionSource? {
        switch self {
        case .application(_, let source), .window(_, _, let source):
            return source
        case .unresolvedDockMinimizedItem:
            return nil
        }
    }

    var windowIdentity: WindowIdentity? {
        switch self {
        case .window(let identity, _, _):
            return identity
        case .application, .unresolvedDockMinimizedItem:
            return nil
        }
    }

    var processIdentifier: pid_t? {
        appIdentity?.processIdentifier
    }

    var logDescription: String {
        switch self {
        case .application(let app, let source):
            return "\(app.logDescription) via \(source.logLabel)"
        case .window(_, let app, let source):
            return "\(app.logDescription) via \(source.logLabel)"
        case .unresolvedDockMinimizedItem:
            return "unresolved minimized Dock item"
        }
    }

    func withSource(_ source: InteractionSource) -> InteractionTarget {
        switch self {
        case .application(let app, _):
            return .application(app, source: source)
        case .window(let identity, let app, _):
            return .window(identity, app: app, source: source)
        case .unresolvedDockMinimizedItem:
            return self
        }
    }
}

extension InteractionSource {
    var logLabel: String {
        switch self {
        case .dockAppItem:
            return "dock-app-item"
        case .dockMinimizedItem:
            return "dock-minimized-item"
        case .titleBar:
            return "title-bar"
        case .browserTabFallback:
            return "browser-tab-fallback"
        }
    }
}

extension InteractionSource {
    var isDockMinimizedItem: Bool {
        if case .dockMinimizedItem = self {
            return true
        }

        return false
    }

    var titleBarHoverSource: TitleBarHoverSource? {
        switch self {
        case .titleBar:
            return .titleBar
        case .browserTabFallback:
            return .browserTabFallback
        case .dockAppItem, .dockMinimizedItem:
            return nil
        }
    }
}
