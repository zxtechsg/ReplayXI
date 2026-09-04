import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class PlayerTrackPresentationSamplingTests: XCTestCase {
    func testPresentationPosePassesThroughEveryAuthoredPosition() {
        let frames = [
            frame(0, x: -7, z: 2, facing: 350),
            frame(0.7, x: -1, z: 5, facing: 8),
            frame(2.4, x: 6, z: -3, facing: 95),
            frame(5, x: 9, z: 4, facing: 185),
        ]
        let track = makeTrack(keyframes: frames)

        for keyframe in frames {
            let pose = track.presentationPose(at: keyframe.time)
            XCTAssertEqual(pose.position.x, keyframe.position.x)
            XCTAssertEqual(pose.position.z, keyframe.position.z)
        }
    }

    func testPresentationVelocityIsContinuousAcrossAnInteriorKnot() {
        let track = makeTrack(keyframes: [
            frame(0, x: 0, z: 0),
            frame(1, x: 4, z: 1),
            frame(2, x: 5, z: 5),
            frame(3, x: 9, z: 6),
        ])
        let knot: TimeInterval = 1
        let step: TimeInterval = 0.002
        let before = track.presentationPose(at: knot - step).position
        let atKnot = track.presentationPose(at: knot).position
        let after = track.presentationPose(at: knot + step).position
        let seconds = Float(step)
        let incomingVelocity = PitchPoint(
            x: (atKnot.x - before.x) / seconds,
            z: (atKnot.z - before.z) / seconds
        )
        let outgoingVelocity = PitchPoint(
            x: (after.x - atKnot.x) / seconds,
            z: (after.z - atKnot.z) / seconds
        )

        XCTAssertEqual(incomingVelocity.x, outgoingVelocity.x, accuracy: 0.08)
        XCTAssertEqual(incomingVelocity.z, outgoingVelocity.z, accuracy: 0.08)
    }

    func testPresentationPositionDoesNotOvershootEitherComponentThroughReversals() {
        let frames = [
            frame(0, x: 0, z: 0),
            frame(1, x: 4, z: 2),
            frame(2, x: 1, z: -3),
            frame(3, x: 3, z: 1),
        ]
        let track = makeTrack(keyframes: frames)

        for (start, end) in zip(frames, frames.dropFirst()) {
            for sampleIndex in 0...100 {
                let fraction = Double(sampleIndex) / 100
                let time = start.time + ((end.time - start.time) * fraction)
                let position = track.presentationPose(at: time).position
                assertWithinSegmentBounds(
                    position.x,
                    start.position.x,
                    end.position.x,
                    component: "x",
                    time: time
                )
                assertWithinSegmentBounds(
                    position.z,
                    start.position.z,
                    end.position.z,
                    component: "z",
                    time: time
                )
            }
        }
    }

    func testPresentationPoseIsBitDeterministicForForwardAndReverseSeeks() {
        let track = makeTrack(keyframes: [
            frame(0, x: -4, z: 2, facing: 340),
            frame(0.8, x: 1, z: 5, facing: 15),
            frame(2.1, x: 7, z: -1, facing: 100),
            frame(3.6, x: 2, z: -6, facing: 210),
            frame(5, x: 8, z: 0, facing: 355),
        ])
        let times = (0...250).map { TimeInterval($0) * 0.02 }
        let forward = times.map { track.presentationPose(at: $0) }

        for (reverseIndex, time) in times.reversed().enumerated() {
            assertPoseBitExact(
                track.presentationPose(at: time),
                forward[forward.count - 1 - reverseIndex]
            )
        }
    }

    func testMalformedAndDuplicateTelemetryFallsBackToFiniteRawPoses() {
        let tracks = [
            makeTrack(keyframes: []),
            makeTrack(keyframes: [frame(1, x: 2, z: 3, facing: 20)]),
            makeTrack(keyframes: [
                frame(0, x: 0, z: 0),
                frame(1, x: 2, z: 3),
                frame(1, x: 8, z: -4),
                frame(2, x: 10, z: 1),
            ]),
            makeTrack(keyframes: [
                frame(0, x: 0, z: 0),
                frame(2, x: 4, z: 2),
                frame(1, x: 6, z: -2),
                frame(3, x: 9, z: 1),
            ]),
            makeTrack(keyframes: [
                frame(0, x: 0, z: 0),
                frame(.nan, x: 3, z: 2),
                frame(2, x: 7, z: -1),
            ]),
            makeTrack(keyframes: [
                frame(0, x: 0, z: 0),
                frame(.infinity, x: 3, z: 2),
                frame(2, x: 7, z: -1),
            ]),
        ]
        let times: [TimeInterval] = [
            -.infinity, -1, 0, 0.5, 1, 1.5, 2, 4, .infinity, .nan,
        ]

        for track in tracks {
            for time in times {
                let presentation = track.presentationPose(at: time)
                XCTAssertTrue(presentation.position.x.isFinite)
                XCTAssertTrue(presentation.position.z.isFinite)
                XCTAssertTrue(presentation.facingDegrees.isFinite)
                assertPoseBitExact(presentation, track.pose(at: time))
            }
        }
    }

    private func makeTrack(keyframes: [MotionKeyframe]) -> PlayerTrack {
        PlayerTrack(
            id: "presentation-sampling-test-player",
            displayName: "Presentation Sampling Test",
            role: "Midfielder",
            shirtNumber: 8,
            team: .home,
            isGoalkeeper: false,
            keyframes: keyframes
        )
    }

    private func frame(
        _ time: TimeInterval,
        x: Float,
        z: Float,
        facing: Float = 0
    ) -> MotionKeyframe {
        MotionKeyframe(
            time: time,
            position: PitchPoint(x: x, z: z),
            facingDegrees: facing
        )
    }

    private func assertWithinSegmentBounds(
        _ value: Float,
        _ first: Float,
        _ second: Float,
        component: String,
        time: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance: Float = 0.000_1
        XCTAssertGreaterThanOrEqual(
            value,
            min(first, second) - tolerance,
            "\(component) undershot its segment at t=\(time)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            value,
            max(first, second) + tolerance,
            "\(component) overshot its segment at t=\(time)",
            file: file,
            line: line
        )
    }

    private func assertPoseBitExact(
        _ actual: PlayerPose,
        _ expected: PlayerPose,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.position.x.bitPattern,
            expected.position.x.bitPattern,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.position.z.bitPattern,
            expected.position.z.bitPattern,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.facingDegrees.bitPattern,
            expected.facingDegrees.bitPattern,
            file: file,
            line: line
        )
    }
}
