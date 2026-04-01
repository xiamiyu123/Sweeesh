import Testing
@testable import Swooshy

struct WindowActionTests {
    @Test
    func areaPreviewAppliesToLayoutActionsThatResizeToTargetFrames() {
        #expect(WindowAction.leftHalf.supportsSnapPreview)
        #expect(WindowAction.rightHalf.supportsSnapPreview)
        #expect(WindowAction.maximize.supportsSnapPreview)
        #expect(WindowAction.center.supportsSnapPreview)

        for action in WindowAction.allCases where
            action != .leftHalf &&
            action != .rightHalf &&
            action != .maximize &&
            action != .center
        {
            #expect(action.supportsSnapPreview == false)
        }
    }
}
