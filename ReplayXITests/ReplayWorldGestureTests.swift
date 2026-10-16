import XCTest
import RealityKit
import simd
@testable import ReplayXI

final class ReplayWorldGestureTests: XCTestCase {
    func testPOVEyeAnchorSitsAheadOfTheBodyAtEachFacing() {
        let position = PitchPoint(x: 2, z: -5)
        let offset = ReplayPOVReference.eyeForwardOffsetMetres
        let cases: [(Float, SIMD3<Float>)] = [
            (0, [2, 0, -5 + offset]), (90, [2 + offset, 0, -5]),
            (180, [2, 0, -5 - offset]), (-90, [2 - offset, 0, -5])
        ]
        for (facing, expected) in cases {
            let eye = ReplayPOVReference.playerEyePoint(
                PlayerPose(position: position, facingDegrees: facing))
            XCTAssertLessThan(simd_distance(eye, expected), 0.000_01)
            XCTAssertEqual(simd_distance(eye, [2, 0, -5]), offset, accuracy: 0.000_01)
        }
    }

    func testEyeAnchorTranslationDoesNotChangeTheCapturedFreeLookBearing() {
        let reference = ReplayPOVReference(scenarioID: "replay", playerID: "winger", rootYaw: 0.6)
        let rotation = simd_quatf(angle: reference.rootYaw, axis: [0, 1, 0])
        for facing: Float in [0, 90, 180] {
            let eye = ReplayPOVReference.playerEyePoint(
                PlayerPose(position: .init(x: 3, z: 4), facingDegrees: facing))
            let translation = -rotation.act(eye)
            XCTAssertLessThan(simd_length(rotation.act(eye) + translation), 0.000_01)
            XCTAssertEqual(reference.rootYaw, 0.6)
        }
        XCTAssertEqual(ReplayPOVReference.playerEyePoint(
            PlayerPose(position: .zero, facingDegrees: .nan)), .zero)
    }

    func testPOVEntryMapsThePlayerEyeToTheTranslatedViewerInsteadOfRoomOrigin() {
        let captured = SIMD2<Float>(2.3, -1.7)
        let reference = ReplayPOVReference(scenarioID: "replay", playerID: "winger",
            rootYaw: 0.6, rootHeight: -0.7, roomXZ: captured)
        let rotation = simd_quatf(angle: reference.rootYaw, axis: [0, 1, 0])
        for (position, facing): (PitchPoint, Float) in [
            (.init(x: 3, z: 4), 0), (.init(x: -7, z: 12), 90), (.init(x: 5, z: -2), 180)
        ] {
            let pose = PlayerPose(position: position, facingDegrees: facing)
            let worldEye = rotation.act(ReplayPOVReference.playerEyePoint(pose)) + reference.rootPosition(for: pose)
            XCTAssertLessThan(simd_distance(worldEye, [captured.x, -0.7, captured.y]), 0.000_01)
        }
        // Moving after entry must leave this checkpoint alone. A new player
        // entry can independently capture the viewer's new room position.
        let pose = PlayerPose(position: .zero, facingDegrees: 25)
        let originalPosition = reference.rootPosition(for: pose)
        let movedViewer = Transform(translation: [4.3, 1.1, -0.7]).matrix
        let next = ReplayPOVReference(scenarioID: "replay", playerID: "teammate",
            rootYaw: reference.rootYaw, rootHeight: reference.rootHeight,
            roomXZ: ReplayPOVReference.roomXZ(from: movedViewer)!)
        XCTAssertEqual(reference.rootPosition(for: pose), originalPosition)
        XCTAssertLessThan(simd_distance(next.rootPosition(for: pose) - originalPosition, [2, 0, 1]), 0.000_01)
    }

    func testPOVRoomPositionRejectsInvalidSamplesAndKeepsLegacyOriginDefault() {
        XCTAssertNil(ReplayPOVReference.roomXZ(from: nil))
        for value: Float in [.nan, .infinity, -.infinity] {
            var transform = matrix_identity_float4x4
            transform.columns.3.x = value
            XCTAssertNil(ReplayPOVReference.roomXZ(from: transform))
            transform = matrix_identity_float4x4
            transform.columns.3.z = value
            XCTAssertNil(ReplayPOVReference.roomXZ(from: transform))
            XCTAssertEqual(ReplayPOVReference(scenarioID: "replay", playerID: "winger",
                rootYaw: 0, roomXZ: [value, 0]).roomXZ, .zero)
        }
        let fallback = Transform(translation: [-2, 1.5, 3]).matrix
        let captured = ReplayPOVReference.roomXZ(from: nil) ?? ReplayPOVReference.roomXZ(from: fallback)
        XCTAssertEqual(captured, SIMD2<Float>(-2, 3))
        let legacy = ReplayPOVReference(scenarioID: "replay", playerID: "winger", rootYaw: 0.3)
        let pose = PlayerPose(position: .init(x: 2, z: 5), facingDegrees: 40)
        XCTAssertEqual(legacy.roomXZ, .zero)
        XCTAssertLessThan(simd_distance(legacy.rootPosition(for: pose),
            -simd_quatf(angle: 0.3, axis: [0, 1, 0]).act(ReplayPOVReference.playerEyePoint(pose))), 0.000_01)
    }

    func testPOVReferenceFacesCurrentPresentedGaze() {
        let yaw = ReplayPOVReference.rootYaw(
            deviceYaw: 0.4, playerFacingDegrees: 90,
            lookYawRadians: 0.2
        )!
        // Player +Z must align to the headset's -Z at the captured instant.
        let worldForward = simd_quatf(angle: yaw + .pi / 2 + 0.2,
                                      axis: [0, 1, 0]).act(SIMD3<Float>(0, 0, 1))
        let headsetForward = simd_quatf(angle: 0.4, axis: [0, 1, 0])
            .act(SIMD3<Float>(0, 0, -1))
        XCTAssertLessThan(simd_distance(worldForward, headsetForward), 0.0001)
    }

    func testRenderedHeadForwardOverridesEstimatedLook() {
        let headYaw: Float = -0.48
        let forward = simd_quatf(angle: headYaw, axis: [0, 1, 0])
            .act(SIMD3<Float>(0, 0, 1))
        let rootYaw = ReplayPOVReference.rootYaw(
            deviceYaw: -0.2, playerFacingDegrees: 135,
            renderedHeadForward: forward, fallbackLookYawRadians: 0.7
        )!
        let worldForward = simd_quatf(angle: rootYaw + 135 * .pi / 180,
                                      axis: [0, 1, 0]).act(forward)
        let headsetForward = simd_quatf(angle: -0.2, axis: [0, 1, 0])
            .act(SIMD3<Float>(0, 0, -1))
        XCTAssertLessThan(simd_distance(worldForward, headsetForward), 0.0001)
    }

    func testMissingOrInvalidRenderedHeadUsesEstimatedGaze() {
        let expected = ReplayPOVReference.rootYaw(
            deviceYaw: 0.3, playerFacingDegrees: 45, lookYawRadians: 0.16
        )!
        let samples: [SIMD3<Float>?] = [nil, .zero, [.nan, 0, 1]]
        for sample in samples {
            let yaw = ReplayPOVReference.rootYaw(
                deviceYaw: 0.3, playerFacingDegrees: 45,
                renderedHeadForward: sample, fallbackLookYawRadians: 0.16
            )!
            XCTAssertEqual(yaw, expected, accuracy: 0.0001)
        }
    }

    func testPOVEntryWaitCommitsFallbackOnceTrackingDeadlineExpires() {
        XCTAssertFalse(ReplayPOVEntryPolicy.shouldUseFallback(startedAt: 10, now: 10.4))
        XCTAssertTrue(ReplayPOVEntryPolicy.shouldUseFallback(startedAt: 10, now: 10.61))
        XCTAssertFalse(ReplayPOVEntryPolicy.shouldUseFallback(startedAt: .nan, now: 11))
        XCTAssertFalse(ReplayPOVEntryPolicy.shouldUseFallback(startedAt: 10, now: .infinity))
    }

    func testPOVEntryAlignsSeatedAndStandingViewersWithTheAvatarEye() {
        let avatarEye: Float = 1.72
        for trackedHeight: Float in [0.9, 1.25, 1.72, 1.95] {
            let height = ReplayPOVReference.rootHeight(
                deviceHeight: trackedHeight, renderedEyeHeight: avatarEye)
            XCTAssertEqual(avatarEye + height, trackedHeight, accuracy: 0.000_01)
            let reference = ReplayPOVReference(scenarioID: "replay", playerID: "winger",
                rootYaw: 0.3, rootHeight: height)
            XCTAssertEqual(reference.rootHeight, height)
            XCTAssertEqual(reference.rootYaw, 0.3)
        }
    }

    func testPOVHeightRejectsInvalidTrackingAndBoundsUnexpectedSamples() {
        for height: Float? in [nil, .nan, .infinity, -.infinity] {
            XCTAssertEqual(ReplayPOVReference.rootHeight(deviceHeight: height, renderedEyeHeight: 1.72), 0)
        }
        for eye: Float? in [nil, .nan, .infinity] {
            XCTAssertEqual(ReplayPOVReference.rootHeight(deviceHeight: 0.9, renderedEyeHeight: eye),
                           0.9 - 1.68, accuracy: 0.000_01)
        }
        for tracked: Float in [-100, 0, 0.4, 2.3, 100] {
            for eye: Float in [-100, 0, 1.8, 100] {
                let height = ReplayPOVReference.rootHeight(deviceHeight: tracked, renderedEyeHeight: eye)
                XCTAssertTrue(height.isFinite)
                XCTAssertGreaterThanOrEqual(height, -1.7)
                XCTAssertLessThanOrEqual(height, 1.2)
            }
        }
        XCTAssertEqual(ReplayPOVReference(scenarioID: "replay", playerID: "winger", rootYaw: 0).rootHeight, 0)
    }

    func testCrouchedEntryKeepsTheLaterStandingTorsoBelowTheFixedEye() {
        for scale: Float in [0.97, 1, 1.03] {
            let nominalHeight: Float = 1.82
            let standingEye = (nominalHeight - 0.11) * scale
            for crown: Float in [0.8, 1.1, 1.45, 1.82] {
                let eye = ReplayPOVReference.safeEyeHeight(crownHeight: crown * scale,
                    nominalHeight: nominalHeight, heightScale: scale)
                XCTAssertEqual(eye, standingEye, accuracy: 0.000_01)
                let seatedHeadset: Float = 0.9
                let fixedOffset = ReplayPOVReference.rootHeight(
                    deviceHeight: seatedHeadset, renderedEyeHeight: eye)
                XCTAssertEqual(standingEye + fixedOffset, seatedHeadset, accuracy: 0.000_01)
                XCTAssertLessThan(1.56 * scale + fixedOffset, seatedHeadset - 0.12,
                                  "The later upright chest/neck cut must remain below the viewer")
            }
            let raised = ReplayPOVReference.safeEyeHeight(crownHeight: 1.95 * scale,
                nominalHeight: nominalHeight, heightScale: scale)
            XCTAssertEqual(raised, (1.95 - 0.11) * scale, accuracy: 0.000_01)
        }
    }

    func testMissingCrownUsesStandingEyeAndInvalidGeometryStaysFinite() {
        for crown: Float? in [nil, .nan, .infinity] {
            XCTAssertEqual(ReplayPOVReference.safeEyeHeight(crownHeight: crown,
                nominalHeight: 1.82, heightScale: 1), 1.71, accuracy: 0.000_01)
        }
        for (height, scale): (Float, Float) in [(.nan, 1), (1.82, .nan), (-1, 1), (1.82, 0)] {
            XCTAssertEqual(ReplayPOVReference.safeEyeHeight(crownHeight: 1.1,
                nominalHeight: height, heightScale: scale), 1.68)
        }
    }

    func testEyeHeightIsCapturedOnceAndDoesNotDriveAContinuousCameraFollow() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertEqual(view.components(separatedBy: "worldTracking.deviceHeight()").count - 1, 1)
        XCTAssertTrue(view.contains("povReference?.playerID == player.id { return }"))
        XCTAssertTrue(view.contains("root.position = povReference.rootPosition(for: playerPose)"))
        XCTAssertEqual(view.components(separatedBy: "let trackedTransform = worldTracking.deviceTransform()").count - 1, 1)
        XCTAssertTrue(view.contains("?? ReplayPOVReference.roomXZ(from: fallbackTransform) ?? .zero"))
        XCTAssertTrue(view.contains("renderedEyeHeight: renderedEntry?.eyeHeight"))
        XCTAssertTrue(view.contains("skin.headMaximumYInPlayerLocalSpace()"))
        XCTAssertTrue(view.contains("ReplayPOVReference.safeEyeHeight("))
    }

    func testPOVSceneIsHiddenUntilItsOwnReferenceIsCaptured() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("root.isEnabled = store.viewMode != .firstPerson || hasCurrentPOVReference"))
        XCTAssertTrue(view.contains("let visible = enabled && (store.viewMode != .firstPerson || hasCurrentPOVReference)"))
        XCTAssertTrue(view.contains("let trackedYaw = worldTracking.deviceYaw()"))
        XCTAssertTrue(view.contains("let deviceYaw = trackedYaw ?? 0"))
        XCTAssertTrue(view.contains("guard worldTracking.hasResolvedWorldStartup else { return }"))
        XCTAssertTrue(view.contains("let startup = Task { await tracking.start() }"))
    }

    func testTwoHandsMoveAndResizeWithBoundsAndReset() {
        var placement = ReplayWorldPlacement()
        placement.update(left: [-0.2, 0, -0.5], right: [0.2, 0, -0.5], allowed: true)
        placement.update(left: [-0.4, 0, -1.0], right: [0.4, 0, -1.0], allowed: true)
        XCTAssertEqual(placement.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(placement.offset.z, -0.5, accuracy: 0.0001)
        placement.update(left: nil, right: nil, allowed: false)
        XCTAssertFalse(placement.isActive)
        XCTAssertEqual(placement.scale, 2, accuracy: 0.0001)
        placement.update(left: [-0.4, 0, -1], right: [0.4, 0, -1], allowed: true)
        placement.update(left: [-4, 2, -8], right: [4, 2, -8], allowed: true)
        XCTAssertEqual(placement.scale, 3, accuracy: 0.0001)
        XCTAssertEqual(placement.offset.z, -2, accuracy: 0.0001)
        placement.reset()
        XCTAssertEqual(placement.scale, 1)
        XCTAssertEqual(placement.offset, .zero)
    }

    func testInvalidHandSampleDoesNotMoveWorld() {
        var placement = ReplayWorldPlacement()
        placement.update(left: [0, 0, 0], right: [.infinity, 0, 0], allowed: true)
        XCTAssertFalse(placement.isActive)
        XCTAssertEqual(placement.scale, 1)
        XCTAssertEqual(placement.offset, .zero)
    }

    func testTouchlineNeverFallsBelowRoomFloorAfterTableOffset() {
        var placement = ReplayWorldPlacement()
        placement.update(left: [-0.2, 0, 0], right: [0.2, 0, 0], allowed: true)
        placement.update(left: [-0.2, -0.6, 0], right: [0.2, -0.6, 0], allowed: true)
        XCTAssertEqual(placement.offset.y, -0.6, accuracy: 0.0001)

        placement.constrainVerticalOffset(minimumY: 0)
        XCTAssertFalse(placement.isActive)
        XCTAssertEqual(placement.offset.y, 0)
        placement.update(left: [-0.2, 0, 0], right: [0.2, 0, 0],
                         allowed: true, minimumOffsetY: 0)
        placement.update(left: [-0.3, -0.4, 0], right: [0.3, -0.4, 0],
                         allowed: true, minimumOffsetY: 0)
        let touchline = ReplayWorldPlacement.apply(
            placement, to: Transform(scale: SIMD3<Float>(repeating: 1),
                rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                translation: [0, 0.02, -4.1])
        )
        XCTAssertGreaterThanOrEqual(touchline.translation.y, 0.02)
        XCTAssertEqual(placement.scale, 1.5, accuracy: 0.0001)
    }

    func testFreshARKitProviderFallbackAndInactiveSurfaceGateAreWired() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let gesture = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/ReplayWorldGesture.swift"), encoding: .utf8)
        XCTAssertTrue(gesture.contains("let fallbackSession = ARKitSession()"))
        XCTAssertTrue(gesture.contains("let fallbackWorld = WorldTrackingProvider()"))
        XCTAssertTrue(gesture.contains("fallbackSession.run([fallbackWorld])"))
        XCTAssertFalse(gesture.contains("try? await session.run([world])"))

        let view = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("surfaceModeIsAvailable && surfacePlacement != nil"))
        XCTAssertTrue(view.contains("&& !hasActiveSurfacePlacement && surfaceScanRequest == nil"))
        XCTAssertTrue(view.contains("hasPlacement: hasActiveSurfacePlacement"))
        XCTAssertTrue(view.contains("if hasActiveSurfacePlacement {"))
    }
}
