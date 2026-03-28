import Foundation
import Observation

extension Notification.Name {
    static let settingsDidChange = Notification.Name("Sweeesh.settingsDidChange")
}

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored
    private let userDefaults: UserDefaults

    var languageOverride: AppLanguage {
        didSet {
            guard oldValue != languageOverride else { return }
            userDefaults.set(languageOverride.rawValue, forKey: Keys.languageOverride)
            notifyDidChange()
        }
    }

    var hotKeysEnabled: Bool {
        didSet {
            guard oldValue != hotKeysEnabled else { return }
            userDefaults.set(hotKeysEnabled, forKey: Keys.hotKeysEnabled)
            notifyDidChange()
        }
    }

    var dockGesturesEnabled: Bool {
        didSet {
            guard oldValue != dockGesturesEnabled else { return }
            userDefaults.set(dockGesturesEnabled, forKey: Keys.dockGesturesEnabled)
            DebugLog.info(DebugLog.settings, "Dock gestures enabled set to \(dockGesturesEnabled)")
            notifyDidChange()
        }
    }

    #if DEBUG
    var debugLoggingEnabled: Bool {
        didSet {
            guard oldValue != debugLoggingEnabled else { return }
            userDefaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled)
            DebugLog.info(DebugLog.settings, "Debug logging enabled set to \(debugLoggingEnabled)")
            notifyDidChange()
        }
    }
    #endif

    var hotKeyBindings: [HotKeyBinding] {
        didSet {
            guard oldValue != hotKeyBindings else { return }
            persistHotKeyBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(hotKeyBindings.count) hot key bindings")
            notifyDidChange()
        }
    }

    var dockGestureBindings: [DockGestureBinding] {
        didSet {
            guard oldValue != dockGestureBindings else { return }
            persistDockGestureBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(dockGestureBindings.count) Dock gesture bindings")
            notifyDidChange()
        }
    }

    var preferredLanguages: [String] {
        languageOverride.preferredLanguages ?? Locale.preferredLanguages
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.languageOverride = AppLanguage(
            rawValue: userDefaults.string(forKey: Keys.languageOverride) ?? ""
        ) ?? .system
        if userDefaults.object(forKey: Keys.hotKeysEnabled) == nil {
            self.hotKeysEnabled = true
        } else {
            self.hotKeysEnabled = userDefaults.bool(forKey: Keys.hotKeysEnabled)
        }
        if userDefaults.object(forKey: Keys.dockGesturesEnabled) == nil {
            self.dockGesturesEnabled = true
        } else {
            self.dockGesturesEnabled = userDefaults.bool(forKey: Keys.dockGesturesEnabled)
        }
        #if DEBUG
        if userDefaults.object(forKey: Keys.debugLoggingEnabled) == nil {
            self.debugLoggingEnabled = false
        } else {
            self.debugLoggingEnabled = userDefaults.bool(forKey: Keys.debugLoggingEnabled)
        }
        #endif
        self.hotKeyBindings = Self.decodeHotKeyBindings(from: userDefaults) ?? HotKeyBindings.defaults
        self.dockGestureBindings = Self.decodeDockGestureBindings(from: userDefaults) ?? DockGestureBindings.defaults
    }

    func localized(_ key: String) -> String {
        L10n.string(key, preferredLanguages: preferredLanguages)
    }

    func hotKeyBinding(for action: WindowAction) -> HotKeyBinding {
        hotKeyBindings.first(where: { $0.action == action }) ?? fallbackBinding(for: action)
    }

    func updateHotKeyKey(_ key: ShortcutKey, for action: WindowAction) {
        let current = hotKeyBinding(for: action)
        updateHotKeyBinding(
            HotKeyBinding(action: action, key: key, modifiers: current.modifiers)
        )
    }

    func updateHotKeyModifiers(_ modifiers: ShortcutModifierSet, for action: WindowAction) {
        let current = hotKeyBinding(for: action)
        updateHotKeyBinding(
            HotKeyBinding(action: action, key: current.key, modifiers: modifiers)
        )
    }

    func updateHotKeyBinding(_ binding: HotKeyBinding) {
        var newBindings = hotKeyBindings

        if let currentIndex = newBindings.firstIndex(where: { $0.action == binding.action }) {
            let currentBinding = newBindings[currentIndex]

            if let conflictIndex = newBindings.firstIndex(where: {
                $0.action != binding.action && $0.key == binding.key && $0.modifiers == binding.modifiers
            }) {
                let conflictingAction = newBindings[conflictIndex].action
                newBindings[conflictIndex] = HotKeyBinding(
                    action: conflictingAction,
                    key: currentBinding.key,
                    modifiers: currentBinding.modifiers
                )
            }

            newBindings[currentIndex] = binding
        } else {
            newBindings.append(binding)
        }

        hotKeyBindings = newBindings.sorted { $0.action.rawValue < $1.action.rawValue }
    }

    func resetHotKeysToDefaults() {
        hotKeyBindings = HotKeyBindings.defaults
    }

    func dockGestureAction(for gesture: DockGestureKind) -> DockGestureAction {
        DockGestureBindings.action(for: gesture, in: dockGestureBindings)
    }

    func updateDockGestureAction(_ action: DockGestureAction, for gesture: DockGestureKind) {
        var newBindings = dockGestureBindings

        if let index = newBindings.firstIndex(where: { $0.gesture == gesture }) {
            if newBindings[index].action == action {
                return
            }
            newBindings[index] = DockGestureBinding(gesture: gesture, action: action)
        } else {
            newBindings.append(DockGestureBinding(gesture: gesture, action: action))
        }

        dockGestureBindings = newBindings.sorted { lhs, rhs in
            lhs.gesture.rawValue < rhs.gesture.rawValue
        }
    }

    func resetDockGestureActionsToDefaults() {
        dockGestureBindings = DockGestureBindings.defaults
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    private func fallbackBinding(for action: WindowAction) -> HotKeyBinding {
        HotKeyBindings.binding(for: action) ?? HotKeyBinding(
            action: action,
            key: .a,
            modifiers: .commandOptionControl
        )
    }

    private func persistHotKeyBindings() {
        if let data = try? JSONEncoder().encode(hotKeyBindings) {
            userDefaults.set(data, forKey: Keys.hotKeyBindings)
        }
    }

    private func persistDockGestureBindings() {
        if let data = try? JSONEncoder().encode(dockGestureBindings) {
            userDefaults.set(data, forKey: Keys.dockGestureBindings)
        }
    }

    private static func decodeHotKeyBindings(from userDefaults: UserDefaults) -> [HotKeyBinding]? {
        guard let data = userDefaults.data(forKey: Keys.hotKeyBindings) else { return nil }
        return try? JSONDecoder().decode([HotKeyBinding].self, from: data)
    }

    private static func decodeDockGestureBindings(from userDefaults: UserDefaults) -> [DockGestureBinding]? {
        guard let data = userDefaults.data(forKey: Keys.dockGestureBindings) else { return nil }
        return try? JSONDecoder().decode([DockGestureBinding].self, from: data)
    }

    private enum Keys {
        static let languageOverride = "settings.languageOverride"
        static let hotKeysEnabled = "settings.hotKeysEnabled"
        static let dockGesturesEnabled = "settings.dockGesturesEnabled"
        #if DEBUG
        static let debugLoggingEnabled = "settings.debugLoggingEnabled"
        #endif
        static let hotKeyBindings = "settings.hotKeyBindings"
        static let dockGestureBindings = "settings.dockGestureBindings"
    }
}
