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

    @Test
    func discardsUnusedApplicationConstraintsAfterOneThousandMisses() {
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
            for: "com.example.cached"
        )

        for round in 0..<1_000 {
            let observation = store.observation(
                for: "com.example.other-\(round)",
                action: .leftHalf
            )
            #expect(observation == nil)
        }

        let cachedObservation = store.observation(
            for: "com.example.cached",
            action: .maximize
        )

        #expect(cachedObservation == nil)
    }

    @Test
    func hitsRefreshConstraintRetentionWindow() {
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
            for: "com.example.cached"
        )

        for round in 0..<999 {
            let observation = store.observation(
                for: "com.example.other-\(round)",
                action: .leftHalf
            )
            #expect(observation == nil)
        }

        let refreshedObservation = store.observation(
            for: "com.example.cached",
            action: .maximize
        )

        #expect(refreshedObservation?.sizeBounds.maximumWidth == 1200)

        for round in 0..<999 {
            let observation = store.observation(
                for: "com.example.another-\(round)",
                action: .leftHalf
            )
            #expect(observation == nil)
        }

        let survivingObservation = store.observation(
            for: "com.example.cached",
            action: .maximize
        )

        #expect(survivingObservation?.sizeBounds.maximumWidth == 1200)
    }
}
