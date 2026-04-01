import CoreGraphics

struct WindowActionPreview: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case area
    }

    enum AxisAnchor: Equatable, Sendable {
        case leadingEdge
        case trailingEdge
        case centered
    }

    struct Observation: Equatable, Sendable {
        var minimumSize: CGSize
        var horizontalAnchor: AxisAnchor?
        var verticalAnchor: AxisAnchor?
    }

    let frame: CGRect
    let style: Style
}

struct WindowLayoutEngine {
    func targetFrame(
        for action: WindowAction,
        currentWindowFrame: CGRect,
        currentVisibleFrame: CGRect
    ) -> CGRect {
        switch action {
        case .leftHalf:
            return leftHalfFrame(in: currentVisibleFrame)
        case .rightHalf:
            return rightHalfFrame(in: currentVisibleFrame)
        case .maximize:
            return currentVisibleFrame.integral
        case .center:
            return currentVisibleFrame.integral
        case .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen:
            return currentWindowFrame
        }
    }

    func preview(
        for action: WindowAction,
        targetFrame: CGRect,
        observation: WindowActionPreview.Observation?
    ) -> WindowActionPreview? {
        guard let previewBehavior = action.previewBehavior else {
            return nil
        }

        switch previewBehavior {
        case .area(let defaultHorizontalAnchor, let defaultVerticalAnchor):
            let frame = areaPreviewFrame(
                targetFrame: targetFrame,
                observation: observation,
                defaultHorizontalAnchor: defaultHorizontalAnchor,
                defaultVerticalAnchor: defaultVerticalAnchor
            )
            return WindowActionPreview(frame: frame, style: .area)
        }
    }

    func screenContainingMost(of windowFrame: CGRect, in screenFrames: [CGRect]) -> CGRect? {
        guard screenFrames.isEmpty == false else {
            return nil
        }

        let midpoint = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let midpointScreen = screenFrames.first(where: { $0.contains(midpoint) }) {
            return midpointScreen
        }

        let intersections = screenFrames.map { frame in
            (frame: frame, overlapArea: frame.intersection(windowFrame).area)
        }

        let maxOverlapArea = intersections.map(\.overlapArea).max() ?? 0
        if maxOverlapArea > 0 {
            let overlapTolerance: CGFloat = 1
            let bestCandidates = intersections
                .filter { abs($0.overlapArea - maxOverlapArea) <= overlapTolerance }
                .map(\.frame)

            if bestCandidates.count == 1 {
                return bestCandidates.first
            }

            if let nearestBestCandidate = nearestScreen(to: midpoint, in: bestCandidates) {
                return nearestBestCandidate
            }
        }

        return nearestScreen(to: midpoint, in: screenFrames)
    }

    func resolvedVisibleFrame(
        preferredPoint: CGPoint?,
        currentWindowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect? {
        let preferredScreenFrame = preferredPoint.flatMap { preferredPoint in
            screenFrames.first { $0.contains(preferredPoint) }
        }

        return preferredScreenFrame ?? screenContainingMost(
            of: currentWindowFrame,
            in: screenFrames
        )
    }

    private func nearestScreen(to point: CGPoint, in screenFrames: [CGRect]) -> CGRect? {
        screenFrames.min { lhs, rhs in
            lhs.center.distance(to: point) < rhs.center.distance(to: point)
        }
    }

    private func areaPreviewFrame(
        targetFrame: CGRect,
        observation: WindowActionPreview.Observation?,
        defaultHorizontalAnchor: WindowActionPreview.AxisAnchor,
        defaultVerticalAnchor: WindowActionPreview.AxisAnchor
    ) -> CGRect {
        let observedMinimumSize = observation?.minimumSize ?? targetFrame.size
        let horizontalAnchor = observation?.horizontalAnchor ?? defaultHorizontalAnchor
        let verticalAnchor = observation?.verticalAnchor ?? defaultVerticalAnchor

        let width = max(targetFrame.width, observedMinimumSize.width)
        let height = max(targetFrame.height, observedMinimumSize.height)

        let originX = anchoredOrigin(
            min: targetFrame.minX,
            max: targetFrame.maxX,
            targetSize: targetFrame.width,
            resolvedSize: width,
            anchor: horizontalAnchor
        )
        let originY = anchoredOrigin(
            min: targetFrame.minY,
            max: targetFrame.maxY,
            targetSize: targetFrame.height,
            resolvedSize: height,
            anchor: verticalAnchor
        )

        return CGRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        ).integral
    }

    private func anchoredOrigin(
        min: CGFloat,
        max: CGFloat,
        targetSize: CGFloat,
        resolvedSize: CGFloat,
        anchor: WindowActionPreview.AxisAnchor
    ) -> CGFloat {
        switch anchor {
        case .leadingEdge:
            return min
        case .trailingEdge:
            return max - resolvedSize
        case .centered:
            return min - ((resolvedSize - targetSize) / 2)
        }
    }

    private func leftHalfFrame(in visibleFrame: CGRect) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: splitX - visibleFrame.minX,
            height: visibleFrame.height
        ).integral
    }

    private func rightHalfFrame(in visibleFrame: CGRect) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        return CGRect(
            x: splitX,
            y: visibleFrame.minY,
            width: visibleFrame.maxX - splitX,
            height: visibleFrame.height
        ).integral
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(point.x - x, point.y - y)
    }
}
