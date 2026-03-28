import CoreGraphics
import Testing
@testable import Swooshy

struct ScreenGeometryTests {
    @Test
    func convertsSingleScreenAXFrameToAppKitCoordinates() {
        let geometry = ScreenGeometry(
            screenFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        )

        let appKitFrame = geometry.appKitFrame(
            fromAXFrame: CGRect(x: 120, y: 90, width: 800, height: 600)
        )

        #expect(appKitFrame == CGRect(x: 120, y: 210, width: 800, height: 600))
    }

    @Test
    func convertsSingleScreenAppKitFrameToAXCoordinates() {
        let geometry = ScreenGeometry(
            screenFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        )

        let axFrame = geometry.axFrame(
            fromAppKitFrame: CGRect(x: 120, y: 210, width: 800, height: 600)
        )

        #expect(axFrame == CGRect(x: 120, y: 90, width: 800, height: 600))
    }

    @Test
    func convertsFramesUsingGlobalDesktopBoundsAcrossDisplays() {
        let geometry = ScreenGeometry(
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1440, height: 900),
                CGRect(x: 1440, y: 0, width: 1280, height: 800),
            ]
        )

        let appKitFrame = geometry.appKitFrame(
            fromAXFrame: CGRect(x: 1600, y: 50, width: 900, height: 700)
        )

        #expect(appKitFrame == CGRect(x: 1600, y: 150, width: 900, height: 700))
        #expect(geometry.axFrame(fromAppKitFrame: appKitFrame) == CGRect(x: 1600, y: 50, width: 900, height: 700))
    }

    @Test
    func convertsFramesRelativeToPrimaryScreenWhenDisplaySitsAboveMainScreen() {
        let geometry = ScreenGeometry(
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1440, height: 900),
                CGRect(x: 80, y: 900, width: 1280, height: 800),
            ]
        )

        let appKitFrame = CGRect(x: 120, y: 980, width: 900, height: 700)
        let axFrame = geometry.axFrame(fromAppKitFrame: appKitFrame)

        #expect(axFrame == CGRect(x: 120, y: -780, width: 900, height: 700))
        #expect(geometry.appKitFrame(fromAXFrame: axFrame) == appKitFrame)
    }
}
