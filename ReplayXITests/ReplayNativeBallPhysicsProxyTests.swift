import Foundation
import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayNativeBallPhysicsProxyTests: XCTestCase {
    func testSprintBootsAndShinsFollowTenMetrePerSecondRoot() throws {
        try check(velocity: [10, 0, 0], maximumTargetError: 0.35)
    }

    func testDiagonalSprintSeparatesRootTravelFromLocalArticulation() throws {
        try check(velocity: [7.2, 0, 5.4], maximumTargetError: 0.35)
    }

    func testOverspeedSourceKeepsLimbsBoundedToNativeTorso() throws {
        try check(velocity: [14, 0, 0], maximumTargetError: nil)
    }

    func testControlledPaceKeepsExistingWorldVelocityBound() throws {
        try check(velocity: [6.5, 0, 0], maximumTargetError: nil)
    }

    func testSprintBudgetBlendIsContinuousAtEightAndNineMetresPerSecond() {
        let weight = ReplayNativeBallPhysicsWorld.limbSprintWeight(forRootSpeed:)
        XCTAssertEqual(weight(7.999), 0)
        XCTAssertEqual(weight(8), 0)
        XCTAssertLessThan(weight(8.001), 0.000_004)
        XCTAssertGreaterThan(weight(8.999), 0.999_996)
        XCTAssertEqual(weight(9), 1)
        XCTAssertEqual(weight(9.001), 1)
        XCTAssertEqual(weight(8.5), 0.5)
        var previous: Float = 0
        for index in 0...100 {
            let value = weight(8 + Float(index) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertTrue((0...1).contains(value))
            previous = value
        }
        XCTAssertEqual(weight(.nan), 0)
    }

    private func check(velocity: SIMD3<Float>, maximumTargetError: Float?) throws {
        let speed = simd_length(velocity)
        let sideways = SIMD3<Float>(-velocity.z, 0, velocity.x) / speed * 1.8
        let initialBall = sideways + [0, 1.2, 0]
        let facing = atan2(velocity.x, velocity.z) * 180 / Float.pi
        let player = PlayerTrack(id: "proxy-sprint", displayName: "Runner", role: "RW", shirtNumber: 11,
            team: .home, isGoalkeeper: false,
            keyframes: [.init(time: 0, position: .zero, facingDegrees: facing),
                        .init(time: 2, position: .init(x: velocity.x * 2, z: velocity.z * 2), facingDegrees: facing)])
        // The freely coasting ball keeps limb proxies active without touching
        // them. No per-step ball placements or player impulses occur here.
        let track = BallTrack(keyframes: [
            .init(time: 0, position: .init(x: initialBall.x, z: initialBall.z), height: initialBall.y),
            .init(time: 2, position: .init(x: initialBall.x + velocity.x * 2,
                                         z: initialBall.z + velocity.z * 2), height: initialBall.y)])
        let world = try ReplayNativeBallPhysicsWorld(gravity: .zero, includePitch: false)
        world.placeBall(position: initialBall, velocity: velocity)
        world.addPlayers([player], ball: track, at: 0)
        let torso = try XCTUnwrap(world.root.findEntity(named: "native-player-proxy-sprint-body"))
        let suffixes = ["left-boot", "right-boot", "left-shin", "right-shin"]
        let limbs = try suffixes.map {
            try XCTUnwrap(world.root.findEntity(named: "native-player-proxy-sprint-\($0)"))
        }
        try world.start()
        var maximumError: Float = 0
        var maximumRelativeSpeed: Float = 0
        var maximumWorldSpeed: Float = 0
        var maximumRootDistance: Float = 0
        var maximumTorsoSpeed: Float = 0
        var allLimbsStayedActive = true
        var rows: [[String: Any]] = []
        for index in 0..<120 {
            let time = Double(index) * ReplayNativeBallPhysics.step
            world.movePlayers([player], ball: track, time: time, delta: ReplayNativeBallPhysics.step)
            let rootVelocity = try XCTUnwrap(torso.components[PhysicsMotionComponent.self]).linearVelocity
            maximumTorsoSpeed = max(maximumTorsoSpeed, simd_length(rootVelocity))
            for limb in limbs {
                allLimbsStayedActive = allLimbsStayedActive && limb.isEnabled
                let motion = try XCTUnwrap(limb.components[PhysicsMotionComponent.self])
                maximumRelativeSpeed = max(maximumRelativeSpeed, simd_length(motion.linearVelocity - rootVelocity))
                maximumWorldSpeed = max(maximumWorldSpeed, simd_length(motion.linearVelocity))
                XCTAssertLessThanOrEqual(simd_length(motion.angularVelocity), 4 * .pi + 0.000_1)
            }
            try world.advance(ReplayNativeBallPhysics.step)
            let sampleTime = time + ReplayNativeBallPhysics.step
            let presented = player.presentationPose(at: sampleTime)
            let geometry = ReplayBallPlayerContact(player: player, ball: track, time: sampleTime,
                                                    presentationPose: presented)
            let targets = [geometry.leftBoot, geometry.rightBoot, geometry.leftShin, geometry.rightShin]
            let rootOffset = torso.position - SIMD3<Float>(presented.position.x, 1.04, presented.position.z)
            for (limb, capsule) in zip(limbs, targets) {
                let target = (capsule.start + capsule.end) * 0.5 + rootOffset
                maximumError = max(maximumError, simd_distance(limb.position, target))
                maximumRootDistance = max(maximumRootDistance,
                    simd_length(SIMD2(limb.position.x - torso.position.x, limb.position.z - torso.position.z)))
            }
            if index % 12 == 11 {
                rows.append(["time": sampleTime, "nativeRootX": torso.position.x,
                    "nativeRootZ": torso.position.z, "maxLimbTargetErrorMetres": maximumError])
            }
        }
        XCTAssertTrue(allLimbsStayedActive, "A disabled proxy cannot prove sprint tracking")
        XCTAssertLessThanOrEqual(maximumTorsoSpeed, 12.001)
        if speed >= 9 { XCTAssertLessThanOrEqual(maximumRelativeSpeed, 8.001) }
        if speed <= 8 { XCTAssertLessThanOrEqual(maximumWorldSpeed, 8.001) }
        XCTAssertLessThanOrEqual(maximumWorldSpeed, 20.001)
        XCTAssertLessThanOrEqual(maximumRootDistance, 1.25,
                                 "An overspeed source must not pull legs away from the native body")
        XCTAssertGreaterThan(simd_length(SIMD2(torso.position.x, torso.position.z)), min(speed, 12) * 0.8)
        if let maximumTargetError {
            XCTAssertLessThanOrEqual(maximumError, maximumTargetError,
                                     "Whole-root travel must not consume the limb articulation budget")
        }
        let report: [String: Any] = ["rootSpeedMetresPerSecond": speed,
            "maxLimbTargetErrorMetres": maximumError,
            "maxLimbDistanceFromNativeRootMetres": maximumRootDistance,
            "maxRelativeSpeedMetresPerSecond": maximumRelativeSpeed,
            "maxWorldSpeedMetresPerSecond": maximumWorldSpeed,
            "maxTorsoSpeedMetresPerSecond": maximumTorsoSpeed,
            "allLimbsStayedActive": allLimbsStayedActive, "samples": rows,
            "scope": "Native kinematic boot/shin motion; coasting non-contact ball; no per-step transform repair"]
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-NativeLimbRootTravel-\(Int(speed)).json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }
}
