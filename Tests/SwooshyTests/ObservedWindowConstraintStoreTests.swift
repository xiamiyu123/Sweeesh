import Testing
@testable import Swooshy

@MainActor
struct ObservedWindowConstraintStoreTests {
    @Test
    func sharedMaximumBoundsApplyAcrossActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )

        let observation = store.observation(
            for: "com.example.app",
            action: .leftHalf
        )

        #expect(observation?.sizeBounds.maximumWidth == 1200)
        #expect(observation?.sizeBounds.maximumHeight == 800)
        #expect(observation?.horizontalAnchor == nil)
        #expect(observation?.verticalAnchor == nil)
    }

    @Test
    func sharedMaximumBoundsDoNotLeakMinimumWidthsAcrossActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: nil,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )

        let rightObservation = store.observation(
            for: "com.example.app",
            action: .rightHalf
        )

        #expect(rightObservation == nil)
    }

    @Test
    func actionSpecificMinimumsMergeWithSharedMaximumBounds() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: nil,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )

        let observation = store.observation(
            for: "com.example.app",
            action: .leftHalf
        )

        #expect(observation?.sizeBounds.minimumWidth == 860)
        #expect(observation?.sizeBounds.maximumWidth == 1200)
        #expect(observation?.sizeBounds.maximumHeight == 800)
        #expect(observation?.horizontalAnchor == .leadingEdge)
        #expect(observation?.verticalAnchor == .leadingEdge)
    }
}
