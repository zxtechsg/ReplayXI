import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackSceneBudgetTests: XCTestCase {
    func testEverySelectedAnnotationKindFitsTheFocusedSystemEnvelope() {
        for kind in CoachMarkKind.allCases {
            let selected = CoachMark(
                kind: kind,
                start: PitchPoint(x: 0, z: 0),
                end: PitchPoint(x: 4, z: 6),
                label: "Selected \(kind.title)",
                revealTime: 0,
                hideTime: 8
            )
            let context = CoachMark(
                kind: .space,
                start: PitchPoint(x: 8, z: 8),
                end: PitchPoint(x: 11, z: 8),
                label: "Context",
                revealTime: 0,
                hideTime: 8
            )
            let marks = [selected, context]
            let visible = PlaybackSceneRenderBudget.visibleAnnotationIDs(
                in: marks,
                priorityIndices: PlaybackSceneRenderBudget.priorityIndices(for: marks),
                at: 1,
                selectedID: selected.id,
                selectedIsEditable: true,
                decisionReviewIsVisible: true
            )
            let admittedDraws = PlaybackSceneRenderBudget.estimatedAnnotationDraws(
                for: marks,
                visibleIDs: visible
            )

            XCTAssertTrue(visible.contains(selected.id), kind.title)
            XCTAssertLessThanOrEqual(
                admittedDraws + PlaybackSceneRenderBudget.selectedEditableOverlayDraws,
                PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit,
                kind.title
            )
        }
    }

    func testArbitraryAnnotationTextMeshCacheRemainsBounded() {
        for index in 0..<(PlaybackSpatialLabels.maximumCachedTextMeshes + 24) {
            _ = PlaybackSpatialLabels.makeAnnotationTag(
                text: "CACHE \(index)",
                color: .white
            )
        }

        XCTAssertLessThanOrEqual(
            PlaybackSpatialLabels.cachedTextMeshCount,
            PlaybackSpatialLabels.maximumCachedTextMeshes
        )
    }
}
