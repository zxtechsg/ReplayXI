import Foundation
import simd
import XCTest
@testable import ReplayXI

/// Run153 documented the authoring gap. Run155 accepts raised edits while
/// retaining the exact legacy save/geometry cases below.
@MainActor
final class CoachMarkRaisedArcCapability153Tests: XCTestCase {
    func testRaisedArcAcceptsShortPitchSpanAcrossExistingEditingAPIs155() throws {
        let store = ReplayStore()
        store.beginDrawing(.arc)
        XCTAssertNil(store.registerPitchTap(.init(x: 26, z: 30)))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: 27, z: 30)))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        let fixed = try XCTUnwrap(store.marks.first { $0.id == created.id && !$0.followsPlayerTracks })
        XCTAssertTrue(store.nudgeCoachMarkElevation(id: fixed.id, target: .end, by: 2))
        let raised = try XCTUnwrap(store.marks.first { $0.id == fixed.id })
        XCTAssertEqual(raised.resolvedStartElevation, 0)
        XCTAssertEqual(raised.resolvedEndElevation, 2)
        store.setPlaying(true, broadcast: false)
        let saved = store.makeSavedReviewState(), marks = store.marks

        let destination = PitchPoint(x: 26.75, z: 30)
        let horizontalLength = ReplayGeometry.distance(raised.start, destination)
        let spatialLength = hypot(horizontalLength, raised.resolvedEndElevation - raised.resolvedStartElevation)
        XCTAssertEqual(horizontalLength, 0.75)
        XCTAssertEqual(spatialLength, sqrt(Float(4.5625)), accuracy: 0.000001)
        XCTAssertGreaterThan(spatialLength, CoachMarkGeometryPolicy.minimumDirectionalLength)
        XCTAssertTrue(store.nudgeCoachMarkEndpoint(id: raised.id, endpoint: .end, by: .init(x: -0.25, z: 0)))
        XCTAssertEqual(store.marks.first { $0.id == raised.id }?.end, destination)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, marks)

        XCTAssertTrue(store.updateCoachMarkGeometry(id: raised.id, start: raised.start,
                                                    end: destination, broadcast: false))
        XCTAssertEqual(store.marks.first { $0.id == raised.id }?.end, destination)
        XCTAssertEqual(store.makeSavedReviewState().marks, saved.marks, "Preview keeps the committed save geometry")
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: raised.id))
        XCTAssertEqual(store.marks, marks)

        let token = UUID()
        store.setPlaying(true, broadcast: false)
        XCTAssertNotNil(store.previewCoachMarkEndpoint(id: raised.id, endpoint: .end,
            gestureID: token, cumulativeDelta: .init(x: -0.25, z: 0)))
        XCTAssertEqual(store.marks.first { $0.id == raised.id }?.end, destination)
        XCTAssertEqual(store.makeSavedReviewState().marks, saved.marks)
        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: raised.id, gestureID: token))
        XCTAssertEqual(store.marks, marks)
        XCTAssertTrue(store.isPlaying, "Cancelled local joystick restores transport")
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        let receipt: [String: Any] = ["horizontalMetres": horizontalLength,
            "spatialMetres": spatialLength, "minimumMetres": CoachMarkGeometryPolicy.minimumDirectionalLength,
            "nudgeAccepted": true, "directPreviewAccepted": true, "joystickPreviewAccepted": true,
            "undoAndCancellationRestoreGeometry": true]
        try attach(receipt, name: "ReplayXI-RaisedArc155-EditAcceptance.json")
    }

    func testBaselineShortRaisedAndVerticalCurvesAreAlreadyAcceptedByReviewAndKeyValidators() throws {
        let store = ReplayStore()
        for horizontal: Float in [0.75, 0] {
            let mark = CoachMark(kind: .arc, start: .init(x: 26, z: 30),
                end: .init(x: 26 + horizontal, z: 30), endElevation: 2,
                curve: .init(bend: 1, lift: 0), label: "Existing raised payload", revealTime: 0)
            XCTAssertFalse(CoachMarkGeometryPolicy.accepts(kind: .arc, start: mark.start, end: mark.end))
            XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: store.selectedScenario))
            let keyed = mark.recordingPose(at: 0).recordingPose(at: 1)
            XCTAssertTrue(keyed.hasValidKeyframes(duration: store.selectedScenario.duration))
            XCTAssertTrue(ReplayStore.isValidReviewMark(keyed, for: store.selectedScenario))
            let decoded = try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(keyed))
            XCTAssertEqual(decoded, keyed)
            XCTAssertTrue(store.appendRemoteCoachMark(decoded))
            XCTAssertTrue(store.reviewLibrary.accepts(store.makeSavedReviewState()))
        }
    }

    func testBaselineLegacyBendCollapsesAtVerticalAndFlipsAcrossThePole() throws {
        let curve = CoachMarkCurve(bend: 1, lift: 0)
        func mark(_ horizontal: Float, curve: CoachMarkCurve) -> CoachMark {
            CoachMark(kind: .arc, start: .zero, end: .init(x: horizontal, z: 0),
                endElevation: 2, curve: curve, label: "Pole diagnostic")
        }
        let before = mark(-0.001, curve: curve), vertical = mark(0, curve: curve), after = mark(0.001, curve: curve)
        let a = curve.point(at: 0.5, for: before)
        let pole = curve.point(at: 0.5, for: vertical)
        let b = curve.point(at: 0.5, for: after)
        XCTAssertEqual(a.z, -1, accuracy: 0.000001)
        XCTAssertEqual(pole, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(b.z, 1, accuracy: 0.000001)
        XCTAssertGreaterThan(simd_distance(a, b), 1.99,
                             "A 2mm endpoint crossing changes the legacy midpoint by about 2m")
        for bend: Float in [1, 3] {
            for roll: Float in [-90, 0, 90] {
                let adjusted = CoachMarkCurve(bend: bend, lift: 0, rollDegrees: roll)
                XCTAssertEqual(adjusted.point(at: 0.5, for: mark(0, curve: adjusted)), pole,
                               "Bend and roll cannot create an offset when the horizontal basis is zero")
            }
        }
        try attach(["endpointMovementMetres": 0.002, "midpointMovementMetres": simd_distance(a, b),
                    "verticalMidpoint": [pole.x, pole.y, pole.z], "scope": "Current legacy math, not a proposed basis"],
                   name: "ReplayXI-RaisedArc153-CurrentPoleGeometry.json")
    }

    private func attach(_ value: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
