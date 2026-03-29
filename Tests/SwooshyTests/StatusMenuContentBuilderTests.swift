import Testing
@testable import Swooshy

struct StatusMenuContentBuilderTests {
    private let builder = StatusMenuContentBuilder()

    @Test
    func menuUsesSimplifiedChineseForChinesePreferredLanguages() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(entries[0].title == "Swooshy")
        #expect(entries[1].title == "授予辅助功能权限")
        #expect(entries[2].title == "刷新权限状态")
        #expect(entries[4].title == "贴靠到左半屏")
        #expect(entries[11].title == "向前切换当前应用窗口")
        #expect(entries[12].title == "向后切换当前应用窗口")
        #expect(entries[14].title == "设置…")
        #expect(entries[16].title == "使用说明")
        #expect(entries[17].title == "退出 Swooshy")
    }

    @Test
    func menuUsesReadyStateWhenPermissionGranted() {
        let entries = builder.makeEntries(
            permissionGranted: true,
            preferredLanguages: ["en-US"]
        )

        #expect(entries[1].title == "Accessibility Access Ready")
        #expect(entries[1].isEnabled == false)
        #expect(entries[4].isEnabled == true)
        #expect(entries[11].isEnabled == true)
        #expect(entries[12].isEnabled == true)
    }

    @Test
    func permissionAndRefreshEntriesAreEnabledWhenPermissionMissing() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["en-US"]
        )

        let enabledEntries = entries.filter(\.isEnabled)
        #expect(enabledEntries.count == 2)
        #expect(enabledEntries.contains { $0.kind == .permission })
        #expect(enabledEntries.contains { $0.kind == .refresh })
    }

    @Test
    func menuFallsBackToEnglishForUnsupportedPreferredLanguages() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["fr-FR"]
        )

        #expect(entries[1].title == "Grant Accessibility Access")
        #expect(entries[14].title == "Settings…")
        #expect(entries[16].title == "How This Works")
    }
}
