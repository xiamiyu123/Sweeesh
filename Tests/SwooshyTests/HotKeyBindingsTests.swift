import AppKit
import Carbon.HIToolbox
import Testing
@testable import Swooshy

struct HotKeyBindingsTests {
    private func expectedMenuFunctionKeyEquivalent(for functionKey: Int, fallback: String) -> String {
        guard let scalar = UnicodeScalar(UInt32(functionKey)) else {
            return fallback
        }

        return String(Character(scalar))
    }

    @Test
    func defaultBindingsCoverEveryWindowAction() {
        #expect(Set(HotKeyBindings.defaults.map(\.action)) == Set(WindowAction.allCases))
    }

    @Test
    func defaultBindingsUseUniqueAccelerators() {
        let accelerators = HotKeyBindings.defaults.map { "\($0.keyCode)-\($0.carbonModifiers)" }
        #expect(Set(accelerators).count == HotKeyBindings.defaults.count)
    }

    @Test
    func shortcutKeyCanResolveFromRecordedKeyCode() {
        #expect(ShortcutKey(keyCode: UInt16(kVK_ANSI_Q)) == .q)
        #expect(ShortcutKey(keyCode: UInt16(kVK_LeftArrow)) == .leftArrow)
    }

    @Test
    func menuKeyEquivalentsRemainStableForArrowShortcuts() {
        #expect(
            ShortcutKey.leftArrow.menuKeyEquivalent ==
                expectedMenuFunctionKeyEquivalent(for: NSLeftArrowFunctionKey, fallback: "←")
        )
        #expect(
            ShortcutKey.rightArrow.menuKeyEquivalent ==
                expectedMenuFunctionKeyEquivalent(for: NSRightArrowFunctionKey, fallback: "→")
        )
        #expect(
            ShortcutKey.upArrow.menuKeyEquivalent ==
                expectedMenuFunctionKeyEquivalent(for: NSUpArrowFunctionKey, fallback: "↑")
        )
        #expect(
            ShortcutKey.downArrow.menuKeyEquivalent ==
                expectedMenuFunctionKeyEquivalent(for: NSDownArrowFunctionKey, fallback: "↓")
        )
    }

    @Test
    func shortcutModifiersResolveFromRecordedFlags() {
        #expect(
            ShortcutModifierSet(
                eventFlags: [.command, .option, .control]
            ) == .commandOptionControl
        )
        #expect(
            ShortcutModifierSet(
                eventFlags: [.command, .shift]
            ) == .commandShift
        )
    }
}
