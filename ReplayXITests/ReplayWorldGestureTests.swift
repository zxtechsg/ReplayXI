import XCTest
import RealityKit
import simd
@testable import ReplayXI

final class ReplayWorldGestureTests: XCTestCase {
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
