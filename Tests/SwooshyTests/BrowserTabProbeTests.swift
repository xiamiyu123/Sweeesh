import Testing
@testable import Swooshy

@MainActor
struct BrowserTabProbeTests {
    @Test
    func supportsMajorBrowsersAndVSCodeEditors() {
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari"
            )
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.microsoft.VSCode",
                localizedName: "Visual Studio Code"
            )
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: nil,
                localizedName: "Cursor"
            )
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.google.antigravity",
                localizedName: "Antigravity"
            )
        )
    }

    @Test
    func rejectsUnsupportedApps() {
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.apple.finder",
                localizedName: "Finder"
            ) == false
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: nil,
                localizedName: "Preview"
            ) == false
        )
    }

    @Test
    func rejectsPageContentTabsForGenericHosts() {
        let ancestry = [
            BrowserTabProbe.TabAncestryNode(
                role: "AXRadioButton",
                subrole: "AXTabButton",
                title: "",
                matchedTabElement: true
            ),
            BrowserTabProbe.TabAncestryNode(
                role: "AXGroup",
                subrole: "AXTabPanel",
                title: "",
                matchedTabElement: false
            ),
            BrowserTabProbe.TabAncestryNode(
                role: "AXGroup",
                subrole: "AXLandmarkMain",
                title: "",
                matchedTabElement: false
            ),
            BrowserTabProbe.TabAncestryNode(
                role: "AXWebArea",
                subrole: "",
                title: "",
                matchedTabElement: false
            ),
        ]

        #expect(
            BrowserTabProbe.acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: .generic
            ) == false
        )
    }

    @Test
    func acceptsSafariStyleTabsForWebKitHosts() {
        let ancestry = [
            BrowserTabProbe.TabAncestryNode(
                role: "AXRadioButton",
                subrole: "AXTabButton",
                title: "",
                matchedTabElement: true
            ),
            BrowserTabProbe.TabAncestryNode(
                role: "AXGroup",
                subrole: "",
                title: "",
                matchedTabElement: false
            ),
        ]

        #expect(
            BrowserTabProbe.acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: .webKit
            )
        )
    }

    @Test
    func acceptsChromiumTabsWithChromeContainers() {
        let ancestry = [
            BrowserTabProbe.TabAncestryNode(
                role: "AXRadioButton",
                subrole: "AXTabButton",
                title: "",
                matchedTabElement: true
            ),
            BrowserTabProbe.TabAncestryNode(
                role: "AXToolbar",
                subrole: "",
                title: "",
                matchedTabElement: false
            ),
        ]

        #expect(
            BrowserTabProbe.acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: .generic
            )
        )
    }
}
