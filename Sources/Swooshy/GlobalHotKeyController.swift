import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyController {
    private let windowActionRunner: WindowActionRunning
    private let alertPresenter: AlertPresenting
    private let settingsStore: SettingsStore
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hasShownPermissionHint = false
    private var settingsObserver: NSObjectProtocol?

    init(
        windowActionRunner: WindowActionRunning,
        alertPresenter: AlertPresenting,
        settingsStore: SettingsStore
    ) {
        self.windowActionRunner = windowActionRunner
        self.alertPresenter = alertPresenter
        self.settingsStore = settingsStore

        installEventHandler()
        syncRegisteredHotKeys()
        observeSettings()
    }

    func shutdown() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        unregisterHotKeys()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncRegisteredHotKeys()
            }
        }
    }

    private func syncRegisteredHotKeys() {
        unregisterHotKeys()

        guard settingsStore.hotKeysEnabled else {
            DebugLog.info(DebugLog.hotkeys, "Global hotkeys disabled")
            return
        }

        DebugLog.info(DebugLog.hotkeys, "Registering global hotkeys")
        registerHotKeys()
    }

    private func registerHotKeys() {
        for action in WindowAction.allCases {
            let binding = settingsStore.hotKeyBinding(for: action)
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: hotKeySignature,
                id: UInt32(binding.action.rawValue + 1)
            )

            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr {
                hotKeyRefs.append(hotKeyRef)
                DebugLog.debug(
                    DebugLog.hotkeys,
                    "Registered hotkey for \(binding.action.title(preferredLanguages: settingsStore.preferredLanguages)) as \(binding.modifiers.displayString)\(binding.menuDisplayKey)"
                )
            } else {
                DebugLog.error(
                    DebugLog.hotkeys,
                    "Failed to register hotkey for \(binding.action.title(preferredLanguages: settingsStore.preferredLanguages)) with status \(status)"
                )
            }
        }
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }

        hotKeyRefs.removeAll()
    }

    private func handleHotKey(withID identifier: UInt32) {
        guard settingsStore.hotKeysEnabled else { return }
        guard let action = WindowAction(rawValue: Int(identifier - 1)) else { return }
        DebugLog.info(DebugLog.hotkeys, "Triggered hotkey for action \(action.title(preferredLanguages: settingsStore.preferredLanguages))")

        do {
            try windowActionRunner.run(action)
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.hotkeys, "Hot key action failed: \(error.localizedDescription)")
        }
    }

    private func handleWindowManagerError(_ error: WindowManagerError) {
        switch error {
        case .accessibilityPermissionMissing:
            guard !hasShownPermissionHint else {
                NSSound.beep()
                return
            }

            hasShownPermissionHint = true
            alertPresenter.show(
                title: settingsStore.localized("alert.permission_required.title"),
                message: settingsStore.localized("alert.permission_required.message")
            )
        default:
            NSSound.beep()
            DebugLog.error(DebugLog.hotkeys, "Hot key action failed: \(error.localizedDescription)")
        }
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        let controller = Unmanaged<GlobalHotKeyController>
            .fromOpaque(userData)
            .takeUnretainedValue()

        Task { @MainActor in
            controller.handleHotKey(withID: hotKeyID.id)
        }

        return noErr
    }

    private let hotKeySignature: OSType = 0x53575348 // "SWSH"
}
