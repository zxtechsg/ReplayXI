import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class PlayerTrackSamplingTests: XCTestCase {
    func testDenseTrackMatchesReferenceLinearSamplerExactlyInBothSeekDirections() {
        let track = makeDenseTrack(frameCount: 2_048, duplicateStride: 29)
        var sampleTimes: [TimeInterval] = [-10, -.infinity, .nan]

        for index in track.keyframes.indices {
            let frame = track.keyframes[index]
            sampleTimes.append(frame.time)
            if index + 1 < track.keyframes.count {
                let nextTime = track.keyframes[index + 1].time
                if nextTime > frame.time {
                    sampleTimes.append(frame.time + ((nextTime - frame.time) * 0.371))
                }
            }
        }
        sampleTimes.append(contentsOf: [track.keyframes.last!.time + 10, .infinity])

        for time in sampleTimes {
            assertPoseExactly(track.pose(at: time), referencePose(for: track, at: time))
            assertMotionExactly(track.motion(at: time), referenceMotion(for: track, at: time))
        }
        for time in sampleTimes.reversed() {
            assertPoseExactly(track.pose(at: time), referencePose(for: track, at: time))
            assertMotionExactly(track.motion(at: time), referenceMotion(for: track, at: time))
        }
    }

    func testDuplicateTimestampBoundaryKeepsPoseLeftContinuousAndMotionRightContinuous() {
        let track = makeTrack(keyframes: [
            frame(0, x: 0, facing: 350),
            frame(1, x: 1, facing: 10),
            frame(1, x: 3, facing: 45),
            frame(1, x: 6, facing: 90),
            frame(2, x: 8, facing: 120),
        ])

        let pose = track.pose(at: 1)
        XCTAssertEqual(pose.position, PitchPoint(x: 1, z: 0))
        XCTAssertEqual(pose.facingDegrees, 370)

        let motion = track.motion(at: 1)
        XCTAssertEqual(motion.distanceTravelled, 6)
        XCTAssertEqual(motion.speedMetresPerSecond, 2)

        let leadingDuplicate = makeTrack(keyframes: [
            frame(0, x: 0),
            frame(0, x: 2),
            frame(1, x: 3),
        ])
        XCTAssertEqual(leadingDuplicate.pose(at: 0).position, PitchPoint(x: 0, z: 0))
        XCTAssertEqual(leadingDuplicate.motion(at: -20).distanceTravelled, 2)
        XCTAssertEqual(leadingDuplicate.motion(at: -20).speedMetresPerSecond, 1)
    }

    func testEmptySingleAndNonFiniteSamplesRetainClampAndFiniteGuardSemantics() {
        let empty = makeTrack(keyframes: [])
        let single = makeTrack(keyframes: [frame(4, x: 7, facing: 225)])

        for time in [-Double.infinity, -1, 4, 20, Double.infinity, Double.nan] {
            assertPoseExactly(empty.pose(at: time), referencePose(for: empty, at: time))
            assertMotionExactly(empty.motion(at: time), referenceMotion(for: empty, at: time))
            assertPoseExactly(single.pose(at: time), referencePose(for: single, at: time))
            assertMotionExactly(single.motion(at: time), referenceMotion(for: single, at: time))
        }

        let ordinary = makeDenseTrack(frameCount: 12, duplicateStride: 5)
        let nanMotion = ordinary.motion(at: .nan)
        XCTAssertTrue(nanMotion.speedMetresPerSecond.isFinite)
        XCTAssertTrue(nanMotion.distanceTravelled.isFinite)
        XCTAssertTrue(nanMotion.locomotionPhase.isFinite)
        assertPoseExactly(ordinary.pose(at: .nan), referencePose(for: ordinary, at: .nan))
        assertMotionExactly(nanMotion, referenceMotion(for: ordinary, at: .nan))
        assertMotionExactly(
            ordinary.motion(at: .infinity),
            referenceMotion(for: ordinary, at: .infinity)
        )
    }

    func testMalformedKeyframeTimesRetainReferenceLinearFallbackSemantics() {
        let malformedTracks = [
            makeTrack(keyframes: [
                frame(0, x: 0),
                frame(3, x: 3),
                frame(1, x: 5),
                frame(4, x: 9),
            ]),
            makeTrack(keyframes: [
                frame(0, x: 0),
                frame(.nan, x: 2),
                frame(2, x: 4),
                frame(4, x: 8),
            ]),
            makeTrack(keyframes: [
                frame(0, x: 0),
                frame(.infinity, x: 4),
                frame(4, x: 8),
            ]),
        ]
        let sampleTimes: [TimeInterval] = [-.infinity, -1, 0, 0.5, 1, 2, 3, 3.5, 4, 8, .infinity, .nan]

        for track in malformedTracks {
            for time in sampleTimes {
                assertPoseExactly(track.pose(at: time), referencePose(for: track, at: time))
                assertMotionExactly(track.motion(at: time), referenceMotion(for: track, at: time))
            }
        }
    }

    func testDerivedSamplingIndexDoesNotChangeCodablePayload() throws {
        let track = makeDenseTrack(frameCount: 24, duplicateStride: 7)
        let encoded = try JSONEncoder().encode(track)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            ["id", "displayName", "role", "shirtNumber", "team", "isGoalkeeper", "keyframes"]
        )
        XCTAssertNil(object["samplingIndex"])

        let decoded = try JSONDecoder().decode(PlayerTrack.self, from: encoded)
        XCTAssertEqual(decoded, track)
        for time in [0.0, 0.3, 2.7, 20.0] {
            assertPoseExactly(decoded.pose(at: time), track.pose(at: time))
            assertMotionExactly(decoded.motion(at: time), track.motion(at: time))
            XCTAssertEqual(decoded.gaitPhase(at: time), track.gaitPhase(at: time))
        }
    }

    func testAnimationSeedAndPhaseSurviveCodableRoundTripForVariedIDs() throws {
        let expected: [(id: String, seed: UInt32)] = [
            ("", 2_166_136_261),
            ("sampling-test-player", 175_403_027),
            ("arg-26", 106_780_438),
            ("é-球", 2_906_375_608),
        ]

        for (id, seed) in expected {
            let track = PlayerTrack(
                id: id, displayName: "Seed test", role: "CM", shirtNumber: 8,
                team: .home, isGoalkeeper: false, keyframes: []
            )
            let decoded = try JSONDecoder().decode(PlayerTrack.self, from: JSONEncoder().encode(track))
            let phase = Float(seed % 628) / 100

            XCTAssertEqual(track.animationSeed, seed)
            XCTAssertEqual(decoded.animationSeed, seed)
            XCTAssertEqual(track.motion(at: 0).locomotionPhase.bitPattern, phase.bitPattern)
            XCTAssertEqual(decoded.gaitPhase(at: 0).bitPattern, phase.bitPattern)
            XCTAssertEqual(decoded.stationaryLocomotion.motion.locomotionPhase.bitPattern, phase.bitPattern)
        }
    }

    func testLargeTelemetryTrackRemainsDeterministicUnderSeekStress() {
        let track = makeDenseTrack(frameCount: 16_384, duplicateStride: 113)
        let duration = track.keyframes.last!.time
        let sampleTimes = (0..<8_192).map { index in
            let scrambled = (index &* 7_919) % 8_192
            return duration * (Double(scrambled) / 8_191)
        }
        let forward = sampleTimes.map { (track.pose(at: $0), track.motion(at: $0)) }

        for (offset, time) in sampleTimes.reversed().enumerated() {
            let expected = forward[forward.count - 1 - offset]
            assertPoseExactly(track.pose(at: time), expected.0)
            assertMotionExactly(track.motion(at: time), expected.1)
        }
    }

    func testLocomotionStateBandsAndImportedRunCompatibilityAreExplicit() {
        XCTAssertEqual(
            PlayerLocomotionSample.classify(speedMetresPerSecond: 0, turnRateDegreesPerSecond: 0),
            .idle
        )
        XCTAssertEqual(
            PlayerLocomotionSample.classify(speedMetresPerSecond: 1.2, turnRateDegreesPerSecond: 0),
            .walk
        )
        XCTAssertEqual(
            PlayerLocomotionSample.classify(speedMetresPerSecond: 2.4, turnRateDegreesPerSecond: 0),
            .jog
        )
        XCTAssertEqual(
            PlayerLocomotionSample.classify(speedMetresPerSecond: 5.8, turnRateDegreesPerSecond: 0),
            .sprint
        )
        XCTAssertEqual(
            PlayerLocomotionSample.classify(speedMetresPerSecond: 2.4, turnRateDegreesPerSecond: -95),
            .cut
        )
        XCTAssertEqual(
            PlayerLocomotionSample.classify(speedMetresPerSecond: 0.1, turnRateDegreesPerSecond: 240),
            .idle,
            "A stationary scan must not be classified as a football cut"
        )

        XCTAssertFalse(PlayerLocomotionState.idle.supportsImportedRunClip)
        XCTAssertFalse(PlayerLocomotionState.walk.supportsImportedRunClip)
        XCTAssertTrue(PlayerLocomotionState.jog.supportsImportedRunClip)
        XCTAssertTrue(PlayerLocomotionState.sprint.supportsImportedRunClip)
        XCTAssertFalse(PlayerLocomotionState.cut.supportsImportedRunClip)
    }

    func testGaitPhaseUsesHumanCadenceAndRemainsContinuousUnderSeek() {
        let walking = makeTrack(keyframes: [
            frame(0, x: 0),
            frame(10, x: 10),
        ])
        let sprinting = makeTrack(keyframes: [
            frame(0, x: 0),
            frame(10, x: 60),
        ])

        let walkingRadiansPerSecond = walking.gaitPhase(at: 2) - walking.gaitPhase(at: 1)
        let sprintRadiansPerSecond = sprinting.gaitPhase(at: 2) - sprinting.gaitPhase(at: 1)
        XCTAssertEqual(
            walkingRadiansPerSecond / (2 * .pi),
            0.96,
            accuracy: 0.000_1,
            "1 m/s should present about 115 total steps per minute"
        )
        XCTAssertEqual(
            sprintRadiansPerSecond / (2 * .pi),
            0.58 + (0.38 * sqrt(Float(6))),
            accuracy: 0.000_1,
            "6 m/s should present about 180 total steps per minute"
        )
        XCTAssertGreaterThan(sprintRadiansPerSecond, walkingRadiansPerSecond)
        XCTAssertLessThan(
            sprintRadiansPerSecond,
            6 * 3.10,
            "sprinting should lengthen stride instead of cycling legs frantically"
        )

        let changingPace = makeTrack(keyframes: [
            frame(0, x: 0),
            frame(4, x: 4),
            frame(6, x: 16),
            frame(8, x: 16),
        ])
        let boundary = changingPace.gaitPhase(at: 4)
        XCTAssertEqual(changingPace.gaitPhase(at: 4), boundary)
        XCTAssertLessThan(abs(changingPace.gaitPhase(at: 3.9999) - boundary), 0.001)
        XCTAssertLessThan(abs(changingPace.gaitPhase(at: 4.0001) - boundary), 0.001)
        XCTAssertEqual(
            changingPace.gaitPhase(at: 8),
            changingPace.gaitPhase(at: 6),
            accuracy: 0.000_1,
            "the gait clock must stop when the player stops"
        )

        let times = (0...160).map { TimeInterval($0) * 0.05 }
        let forward = times.map { changingPace.gaitPhase(at: $0) }
        for (index, time) in times.reversed().enumerated() {
            XCTAssertEqual(changingPace.gaitPhase(at: time), forward[forward.count - 1 - index])
        }
    }

    func testPresentationLocomotionCapturesAccelerationAndPlantedCutDeterministically() {
        let accelerating = makeTrack(keyframes: [
            frame(0, x: 0),
            frame(1, x: 1),
            frame(2, x: 4),
        ])
        let acceleration = accelerating.locomotion(at: 1.2)
        XCTAssertEqual(acceleration.state, .jog)
        XCTAssertEqual(acceleration.speedMetresPerSecond, 2.4984, accuracy: 0.000_1)
        XCTAssertGreaterThan(acceleration.accelerationMetresPerSecondSquared, 4)
        XCTAssertEqual(acceleration, accelerating.locomotion(at: 1.2))

        let cutting = makeTrack(keyframes: [
            frame(0, x: -2, z: 0, facing: 0),
            frame(1, x: 0, z: 0, facing: 0),
            frame(2, x: 0, z: 2, facing: 90),
        ])
        // Monotone presentation interpolation deliberately eases into the
        // authored corner instead of teleporting between two linear velocity
        // vectors. At the knot the player is in a brief planted slowdown; the
        // cut classification becomes active as the player drives away.
        let planted = cutting.locomotion(at: 1)
        XCTAssertEqual(planted.state, .walk)
        XCTAssertLessThan(planted.speedMetresPerSecond, 0.5)
        XCTAssertGreaterThan(abs(planted.turnRateDegreesPerSecond), 300)

        let first = cutting.locomotion(at: 1.3)
        _ = cutting.locomotion(at: 1.8)
        let seeked = cutting.locomotion(at: 1.3)

        XCTAssertEqual(first, seeked)
        XCTAssertEqual(first.state, .cut)
        XCTAssertEqual(first.speedMetresPerSecond, 1.8312, accuracy: 0.000_1)
        XCTAssertGreaterThan(abs(first.turnRateDegreesPerSecond), 80)

        for time in stride(from: 2.0, through: 0.0, by: -0.05) {
            let reverse = cutting.locomotion(at: time)
            XCTAssertEqual(reverse, cutting.locomotion(at: time))
            XCTAssertTrue(reverse.speedMetresPerSecond.isFinite)
            XCTAssertTrue(reverse.accelerationMetresPerSecondSquared.isFinite)
            XCTAssertTrue(reverse.turnRateDegreesPerSecond.isFinite)
        }
    }

    private func makeDenseTrack(frameCount: Int, duplicateStride: Int) -> PlayerTrack {
        var timestamp: TimeInterval = 0
        var keyframes: [MotionKeyframe] = []
        keyframes.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            if index > 0, duplicateStride <= 0 || index % duplicateStride != 0 {
                timestamp += 0.011 + (Double(index % 9) * 0.003)
            }
            let phase = Float(index) * 0.037
            keyframes.append(
                MotionKeyframe(
                    time: timestamp,
                    position: PitchPoint(
                        x: (Float(index) * 0.013) + (sin(phase) * 4.2),
                        z: (Float(index) * 0.021) + (cos(phase * 0.73) * 7.1)
                    ),
                    facingDegrees: Float((index * 47) % 720) - 180
                )
            )
        }
        return makeTrack(keyframes: keyframes)
    }

    private func makeTrack(keyframes: [MotionKeyframe]) -> PlayerTrack {
        PlayerTrack(
            id: "sampling-test-player",
            displayName: "Sampling Test",
            role: "Right winger",
            shirtNumber: 7,
            team: .home,
            isGoalkeeper: false,
            keyframes: keyframes
        )
    }

    private func frame(
        _ time: TimeInterval,
        x: Float,
        z: Float = 0,
        facing: Float = 0
    ) -> MotionKeyframe {
        MotionKeyframe(
            time: time,
            position: PitchPoint(x: x, z: z),
            facingDegrees: facing
        )
    }

    /// Frozen copy of the pre-optimization implementation. It is intentionally
    /// linear so dense equivalence checks independently protect every boundary.
    private func referencePose(for track: PlayerTrack, at time: TimeInterval) -> PlayerPose {
        guard let first = track.keyframes.first else {
            return PlayerPose(position: .zero, facingDegrees: 0)
        }
        guard track.keyframes.count > 1, time > first.time else {
            return PlayerPose(position: first.position, facingDegrees: first.facingDegrees)
        }
        guard let last = track.keyframes.last else {
            return PlayerPose(position: first.position, facingDegrees: first.facingDegrees)
        }
        guard time < last.time else {
            return PlayerPose(position: last.position, facingDegrees: last.facingDegrees)
        }

        for (start, end) in zip(track.keyframes, track.keyframes.dropFirst()) {
            guard time >= start.time, time <= end.time else { continue }
            let span = max(end.time - start.time, 0.000_1)
            let fraction = Float((time - start.time) / span)
            return PlayerPose(
                position: start.position.interpolated(to: end.position, fraction: fraction),
                facingDegrees: ReplayGeometry.interpolateAngle(
                    from: start.facingDegrees,
                    to: end.facingDegrees,
                    fraction: fraction
                )
            )
        }

        return PlayerPose(position: last.position, facingDegrees: last.facingDegrees)
    }

    private func referenceMotion(
        for track: PlayerTrack,
        at time: TimeInterval
    ) -> PlayerMotionState {
        let phaseOffset = Float(
            track.id.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
                (partial ^ UInt32(byte)) &* 16_777_619
            } % 628
        ) / 100
        guard track.keyframes.count > 1, let first = track.keyframes.first else {
            return PlayerMotionState(
                speedMetresPerSecond: 0,
                distanceTravelled: 0,
                locomotionPhase: phaseOffset
            )
        }

        let clampedTime = max(time, first.time)
        var distanceTravelled: Float = 0
        var speed: Float = 0

        for (start, end) in zip(track.keyframes, track.keyframes.dropFirst()) {
            let segmentDuration = max(end.time - start.time, 0.000_1)
            let segmentDistance = ReplayGeometry.distance(start.position, end.position)

            if clampedTime >= end.time {
                distanceTravelled += segmentDistance
                continue
            }

            if clampedTime >= start.time {
                let fraction = Float((clampedTime - start.time) / segmentDuration)
                distanceTravelled += segmentDistance * min(max(fraction, 0), 1)
                speed = segmentDistance / Float(segmentDuration)
            }
            break
        }

        if let last = track.keyframes.last, clampedTime >= last.time {
            speed = 0
        }

        return PlayerMotionState(
            speedMetresPerSecond: speed,
            distanceTravelled: distanceTravelled,
            locomotionPhase: (distanceTravelled * 3.10) + phaseOffset
        )
    }

    private func assertPoseExactly(
        _ actual: PlayerPose,
        _ expected: PlayerPose,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.position.x.bitPattern, expected.position.x.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.position.z.bitPattern, expected.position.z.bitPattern, file: file, line: line)
        XCTAssertEqual(actual.facingDegrees.bitPattern, expected.facingDegrees.bitPattern, file: file, line: line)
    }

    private func assertMotionExactly(
        _ actual: PlayerMotionState,
        _ expected: PlayerMotionState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.speedMetresPerSecond.bitPattern,
            expected.speedMetresPerSecond.bitPattern,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.distanceTravelled.bitPattern,
            expected.distanceTravelled.bitPattern,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.locomotionPhase.bitPattern,
            expected.locomotionPhase.bitPattern,
            file: file,
            line: line
        )
    }
}
