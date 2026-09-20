import XCTest
@testable import ReplayXI

final class ReplaySlowRunAdmissionTests: XCTestCase {
    func testExactSpeedTurnBoundariesAndPlateau() {
        for speed: Float in [-1, 0, 0.5, 1, 2.9, 3, 8] {
            XCTAssertEqual(weight(speed: speed), 0, "speed \(speed)")
        }
        for speed: Float in [1.9, 2, 2.2] {
            for turn: Float in [-20, 0, 20] {
                XCTAssertEqual(weight(speed: speed, turn: turn), 1)
            }
        }
        for turn: Float in [-360, -38, 38, 360] {
            XCTAssertEqual(weight(speed: 2, turn: turn), 0)
        }
        XCTAssertEqual(weight(speed: 1.45), 0.5, accuracy: 0.000001)
        XCTAssertEqual(weight(speed: 2.55), 0.5, accuracy: 0.000001)
        XCTAssertEqual(weight(speed: 2, turn: 29), 0.5, accuracy: 0.000001)
        XCTAssertEqual(weight(speed: 1.45, turn: -29), 0.25, accuracy: 0.000001)
    }

    func testBroadQuinticRampsAreBoundedMonotoneAndSymmetric() {
        var previousRise: Float = 0
        var previousFall: Float = 1
        var previousTurn: Float = 1
        for index in 0...1_000 {
            let t = Float(index) / 1_000
            let rise = weight(speed: 1 + 0.9 * t)
            let fall = weight(speed: 2.2 + 0.7 * t)
            let turn = weight(speed: 2, turn: 20 + 18 * t)
            for value in [rise, fall, turn] {
                XCTAssertTrue(value.isFinite)
                XCTAssertTrue((0...1).contains(value))
            }
            XCTAssertGreaterThanOrEqual(rise, previousRise)
            XCTAssertLessThanOrEqual(fall, previousFall)
            XCTAssertLessThanOrEqual(turn, previousTurn)
            XCTAssertEqual(turn, weight(speed: 2, turn: -(20 + 18 * t)))
            XCTAssertEqual(rise + fall, 1, accuracy: 0.000002)
            previousRise = rise
            previousFall = fall
            previousTurn = turn
        }
        // Smootherstep at one-quarter/three-quarters: a broad ramp, not a
        // nearly binary threshold disguised by an easing function.
        XCTAssertEqual(weight(speed: 1.225), 0.103515625, accuracy: 0.000001)
        XCTAssertEqual(weight(speed: 1.675), 0.896484375, accuracy: 0.000001)
        XCTAssertEqual(weight(speed: 2.375), 0.896484375, accuracy: 0.000001)
        XCTAssertEqual(weight(speed: 2.725), 0.103515625, accuracy: 0.000001)
    }

    func testSpeedAndTurnJoinsHaveContinuousFlatEndpointSlopes() {
        let step: Float = 0.001
        for speed: Float in [1, 1.9, 2.2, 2.9] {
            let centre = weight(speed: speed)
            let leftSlope = (centre - weight(speed: speed - step)) / step
            let rightSlope = (weight(speed: speed + step) - centre) / step
            XCTAssertLessThan(abs(leftSlope), 0.0005, "left join at \(speed)")
            XCTAssertLessThan(abs(rightSlope), 0.0005, "right join at \(speed)")
        }
        for turn: Float in [-38, -20, 20, 38] {
            let centre = weight(speed: 2, turn: turn)
            let leftSlope = (centre - weight(speed: 2, turn: turn - step)) / step
            let rightSlope = (weight(speed: 2, turn: turn + step) - centre) / step
            XCTAssertLessThan(abs(leftSlope), 0.0005)
            XCTAssertLessThan(abs(rightSlope), 0.0005)
        }
    }

    func testEveryNumericFieldRejectsNonfiniteValuesAndBothSpeedsRejectNegatives() {
        for invalid in [Float.nan, .infinity, -.infinity] {
            XCTAssertEqual(weight(speed: invalid), 0)
            XCTAssertEqual(weight(speed: 2, turn: invalid), 0)
            XCTAssertEqual(weight(speed: 2, acceleration: invalid), 0)
            XCTAssertEqual(weight(speed: 2, sourceSpeed: invalid), 0)
            XCTAssertEqual(weight(speed: 2, distance: invalid), 0)
            XCTAssertEqual(weight(speed: 2, phase: invalid), 0)
        }
        XCTAssertEqual(weight(speed: -0.001), 0)
        XCTAssertEqual(weight(speed: 2, sourceSpeed: -0.001), 0)
        XCTAssertEqual(weight(speed: 2, acceleration: -2), weight(speed: 2, acceleration: 2),
                       "Acceleration is validated, not a new discontinuous admission gate")
    }

    func testDiscreteClassificationAndScalarMotionDoNotInventADirectionGate() {
        XCTAssertEqual(weight(speed: 1.65, state: .walk), weight(speed: 1.65, state: .jog))
        XCTAssertGreaterThan(weight(speed: 1.65, state: .walk), 0)
        XCTAssertEqual(weight(speed: 2, sourceSpeed: 0, distance: 0, phase: -2), 1,
                       "Segment speed, cumulative distance and phase carry no travel-versus-facing direction")
        let speeds: [Float] = [0, 1, 1.225, 1.9, 2.2, 2.55, 2.9, 8]
        let forward = speeds.map { weight(speed: $0) }
        let reverse = speeds.reversed().map { weight(speed: $0) }
        XCTAssertEqual(forward, Array(reverse.reversed()), "No previous-frame state may affect a seek")
    }

    func testDirectionGateBoundariesAndNonfiniteInputs() {
        for yaw: Float in [-0.22, -0.1, 0, 0.1, 0.22] {
            XCTAssertEqual(ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw), 1)
        }
        for yaw: Float in [-Float.pi, -0.72, 0.72, Float.pi] {
            XCTAssertEqual(ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw), 0)
        }
        for invalid in [Float.nan, .infinity, -.infinity] {
            XCTAssertEqual(ReplaySlowRunAdmission.directionWeight(localTravelYaw: invalid), 0)
        }
        XCTAssertEqual(ReplaySlowRunAdmission.directionWeight(localTravelYaw: 0.345), 0.896484375,
                       accuracy: 0.000001)
        XCTAssertEqual(ReplaySlowRunAdmission.directionWeight(localTravelYaw: 0.47), 0.5,
                       accuracy: 0.000001)
        XCTAssertEqual(ReplaySlowRunAdmission.directionWeight(localTravelYaw: 0.595), 0.103515625,
                       accuracy: 0.000001)
    }

    func testDirectionGateIsSymmetricMonotoneAndContinuousAtBothJoins() {
        var previous: Float = 1
        for index in 0...1_000 {
            let yaw = Float(0.22) + 0.5 * Float(index) / 1_000
            let value = ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw)
            XCTAssertTrue(value.isFinite)
            XCTAssertTrue((0...1).contains(value))
            XCTAssertLessThanOrEqual(value, previous)
            XCTAssertEqual(value, ReplaySlowRunAdmission.directionWeight(localTravelYaw: -yaw))
            previous = value
        }
        let step: Float = 0.001
        for yaw: Float in [-0.72, -0.22, 0.22, 0.72] {
            let centre = ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw)
            let leftSlope = (centre - ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw - step)) / step
            let rightSlope = (ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw + step) - centre) / step
            XCTAssertLessThan(abs(leftSlope), 0.0005, "left join at \(yaw)")
            XCTAssertLessThan(abs(rightSlope), 0.0005, "right join at \(yaw)")
        }
    }

    func testRepresentativeAccelerationKeepsWeightDerivativeBelowNarrow43MillisecondBlend() throws {
        // Pure admission math at an explicit synthetic acceleration. These
        // are not measured player kinematics or a visual/contact quality claim.
        let acceleration: Float = 2
        let sampleInterval: Float = 1 / 120
        let narrowDuration: Float = 0.043
        let narrowPeakSlope: Float = 1.875 / narrowDuration
        var rows: [[String: Any]] = []
        for (name, startSpeed, endSpeed) in [("rise", Float(1), Float(1.9)), ("fall", Float(2.2), Float(2.9))] {
            let duration = (endSpeed - startSpeed) / acceleration
            let theoreticalPeakSlope = 1.875 / duration
            var largestDelta: Float = 0
            var previous = weight(speed: startSpeed, acceleration: acceleration)
            var samples: [Float] = [previous]
            for index in 1...Int(ceil(duration / sampleInterval)) {
                let time = min(Float(index) * sampleInterval, duration)
                let value = weight(speed: startSpeed + acceleration * time, acceleration: acceleration)
                largestDelta = max(largestDelta, abs(value - previous))
                samples.append(value)
                previous = value
            }
            XCTAssertGreaterThanOrEqual(duration, 0.35 - 0.000001)
            XCTAssertLessThanOrEqual(largestDelta, theoreticalPeakSlope * sampleInterval + 0.000002)
            XCTAssertLessThan(theoreticalPeakSlope, narrowPeakSlope / 8)
            XCTAssertEqual(samples.first, name == "rise" ? 0 : 1)
            XCTAssertEqual(samples.last, name == "rise" ? 1 : 0)
            rows.append(["ramp": name, "accelerationMetresPerSecondSquared": acceleration,
                "durationSeconds": duration, "sampleRateHz": 120,
                "largestPerSampleWeightChange": largestDelta, "analyticPeakWeightDerivativePerSecond": theoreticalPeakSlope,
                "comparison43msPeakWeightDerivativePerSecond": narrowPeakSlope])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "scope": "Synthetic admission-weight math only; no motion-quality, floor-contact or FPS claim", "ramps": rows
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SlowRunAdmission151.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func weight(speed: Float, turn: Float = 0, acceleration: Float = 0,
                        sourceSpeed: Float = 2, distance: Float = 3, phase: Float = 1,
                        state: PlayerLocomotionState? = nil) -> Float {
        ReplaySlowRunAdmission.weight(locomotion: .init(
            motion: .init(speedMetresPerSecond: sourceSpeed, distanceTravelled: distance, locomotionPhase: phase),
            speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: acceleration,
            turnRateDegreesPerSecond: turn,
            state: state ?? PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                           turnRateDegreesPerSecond: turn)))
    }
}
