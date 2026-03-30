import CoreGraphics

struct ScreenGeometry {
    private let primaryScreenMaxY: CGFloat

    init(screenFrames: [CGRect]) {
        self.primaryScreenMaxY = screenFrames.first?.maxY ?? 0
    }

    func appKitFrame(fromAXFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenMaxY - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        ).integral
    }

    func axFrame(fromAppKitFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        ).integral
    }

    func axPoint(fromAppKitPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x,
            y: primaryScreenMaxY - point.y
        )
    }
}
