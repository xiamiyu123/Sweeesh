import AppKit
import Combine
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    init(
        settingsStore: SettingsStore,
        permissionManager: AccessibilityPermissionManaging,
        onOpenSettings: @escaping () -> Void
    ) {
        var windowReference: NSWindow?
        let rootView = WelcomeView(
            title: settingsStore.localized("welcome.title"),
            message: settingsStore.localized("welcome.message"),
            permissionStep: settingsStore.localized("welcome.step.permission"),
            settingsStep: settingsStore.localized("welcome.step.settings"),
            permissionGrantedText: settingsStore.localized("welcome.permission.granted"),
            permissionMissingText: settingsStore.localized("welcome.permission.missing"),
            grantPermissionActionTitle: settingsStore.localized("welcome.grant_permission_action"),
            refreshPermissionActionTitle: settingsStore.localized("welcome.refresh_permission_action"),
            openSettingsActionTitle: settingsStore.localized("welcome.open_settings_action"),
            secondaryActionTitle: settingsStore.localized("welcome.secondary_action"),
            initialPermissionGranted: permissionManager.isTrusted(promptIfNeeded: false),
            onRequestPermission: {
                permissionManager.isTrusted(promptIfNeeded: true)
            },
            onRefreshPermissionState: {
                permissionManager.isTrusted(promptIfNeeded: false)
            },
            onOpenSettings: {
                onOpenSettings()
                windowReference?.close()
            },
            onDismiss: {
                windowReference?.close()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        windowReference = window

        window.setContentSize(NSSize(width: 580, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.title = settingsStore.localized("welcome.window.title")

        super.init(window: window)
        self.window?.delegate = self
    }

    func shutdown() {
        window?.delegate = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct WelcomeView: View {
    let title: String
    let message: String
    let permissionStep: String
    let settingsStep: String
    let permissionGrantedText: String
    let permissionMissingText: String
    let grantPermissionActionTitle: String
    let refreshPermissionActionTitle: String
    let openSettingsActionTitle: String
    let secondaryActionTitle: String
    let onRequestPermission: () -> Bool
    let onRefreshPermissionState: () -> Bool
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    @State private var permissionGranted: Bool
    private let permissionRefreshTimer = Timer
        .publish(every: 1.0, on: .main, in: .common)
        .autoconnect()

    init(
        title: String,
        message: String,
        permissionStep: String,
        settingsStep: String,
        permissionGrantedText: String,
        permissionMissingText: String,
        grantPermissionActionTitle: String,
        refreshPermissionActionTitle: String,
        openSettingsActionTitle: String,
        secondaryActionTitle: String,
        initialPermissionGranted: Bool,
        onRequestPermission: @escaping () -> Bool,
        onRefreshPermissionState: @escaping () -> Bool,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.permissionStep = permissionStep
        self.settingsStep = settingsStep
        self.permissionGrantedText = permissionGrantedText
        self.permissionMissingText = permissionMissingText
        self.grantPermissionActionTitle = grantPermissionActionTitle
        self.refreshPermissionActionTitle = refreshPermissionActionTitle
        self.openSettingsActionTitle = openSettingsActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.onRequestPermission = onRequestPermission
        self.onRefreshPermissionState = onRefreshPermissionState
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
        _permissionGranted = State(initialValue: initialPermissionGranted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))

            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(index: 1, text: permissionStep)
                stepRow(index: 2, text: settingsStep)
            }

            HStack(spacing: 8) {
                Image(systemName: permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissionGranted ? Color.green : Color.orange)
                Text(permissionGranted ? permissionGrantedText : permissionMissingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(refreshPermissionActionTitle) {
                    refreshPermissionState()
                }
                .controlSize(.small)
            }

            Spacer()

            HStack {
                Spacer()
                Button(secondaryActionTitle) {
                    onDismiss()
                }
                Button(grantPermissionActionTitle) {
                    permissionGranted = onRequestPermission()
                    refreshPermissionState()
                }
                .disabled(permissionGranted)
                Button(openSettingsActionTitle) {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(permissionGranted == false)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 400)
        .onAppear(perform: refreshPermissionState)
        .onReceive(permissionRefreshTimer) { _ in
            refreshPermissionState()
        }
    }

    private func stepRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index).")
                .font(.headline)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func refreshPermissionState() {
        permissionGranted = onRefreshPermissionState()
    }
}
