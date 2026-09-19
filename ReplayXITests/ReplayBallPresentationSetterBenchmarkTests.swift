import Dispatch
import RealityKit
import XCTest

/// A test-only comparison of the ten setters in the ball presentation block.
/// This does not change shipping code or skip a presentation/sampler update.
@MainActor
final class ReplayBallPresentationSetterBenchmarkTests: XCTestCase {
    private struct DesiredState {
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let ballScale: SIMD3<Float>
        let shadowPosition: SIMD3<Float>
        let shadowScale: SIMD3<Float>
        let emphasisPosition: SIMD3<Float>
        let emphasisScale: SIMD3<Float>
        let shown: Bool
        let emphasized: Bool
    }

    private struct Subjects {
        let parent: Entity
        let ball: ModelEntity
        let shadow: ModelEntity
        let emphasis: ModelEntity
    }

    private struct Batch: Codable {
        let pair: Int
        let order: String
        let directNanoseconds: UInt64
        let guardedNanoseconds: UInt64
    }

    private struct Phase: Codable {
        let name: String
        let requestsPerBatch: Int
        let batches: [Batch]
        let directMedianNanoseconds: Double
        let guardedMedianNanoseconds: Double
        let pairedGuardedToDirectMedianRatio: Double
    }

    private struct Report: Codable {
        let qualification: String
        let phases: [Phase]
    }

    func testDirectSettersVersusExactLiveGuardsProduceBoundedNativeTimingReceipt() throws {
        let subjects = makeSubjects()
        let requests = 2_048
        let pairs = 12
        let moving = (0..<128).map { state(frame: $0) }
        let held = Array(repeating: state(frame: 12), count: 128)
        let mostlyHeld = (0..<128).map { state(frame: $0 / 8) }
        let phases: [(String, [DesiredState])] = [
            ("paused", held), ("moving_every_request", moving),
            ("seven_of_eight_requests_held", mostlyHeld)
        ]
        var results: [Phase] = []
        for (name, states) in phases {
            // Resource creation, setup, warmup and state assertions are untimed.
            writeDirect(states[0], to: subjects)
            _ = timeDirect(subjects, states: states, requests: 512)
            writeDirect(states[0], to: subjects)
            _ = timeGuarded(subjects, states: states, requests: 512)
            var batches: [Batch] = []
            for pair in 0..<pairs {
                let directFirst = pair.isMultiple(of: 2)
                let direct: UInt64
                let guarded: UInt64
                // Both variants use the same three native entities and reset
                // to the same state. Their order alternates to expose bias.
                if directFirst {
                    writeDirect(states[0], to: subjects)
                    direct = timeDirect(subjects, states: states, requests: requests)
                    assertState(subjects, equals: states[0])
                    writeDirect(states[0], to: subjects)
                    guarded = timeGuarded(subjects, states: states, requests: requests)
                    assertState(subjects, equals: states[0])
                } else {
                    writeDirect(states[0], to: subjects)
                    guarded = timeGuarded(subjects, states: states, requests: requests)
                    assertState(subjects, equals: states[0])
                    writeDirect(states[0], to: subjects)
                    direct = timeDirect(subjects, states: states, requests: requests)
                    assertState(subjects, equals: states[0])
                }
                batches.append(Batch(pair: pair, order: directFirst ? "direct_then_guarded" : "guarded_then_direct",
                                     directNanoseconds: direct, guardedNanoseconds: guarded))
            }
            results.append(Phase(
                name: name, requestsPerBatch: requests, batches: batches,
                directMedianNanoseconds: median(batches.map { Double($0.directNanoseconds) }),
                guardedMedianNanoseconds: median(batches.map { Double($0.guardedNanoseconds) }),
                pairedGuardedToDirectMedianRatio: median(batches.map {
                    Double($0.guardedNanoseconds) / max(Double($0.directNanoseconds), 1)
                })
            ))
        }
        let report = Report(
            qualification: "Test-only synchronous native RealityKit property-access microbenchmark. Three parented ModelEntities, precomputed identical desired states, 12 alternating-order pairs of 2048 requests per phase. No renderer, physics, frame pacing or shipping updates are measured. Every request is evaluated; no timestamp/cache skip. DEBUG timings include unoptimized Swift overhead and must not be presented as device CPU/FPS savings. Raw batches are retained; no timing pass/fail threshold.",
            phases: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-BallSetterMicrobenchmark.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGuardsMatchEveryForwardReverseRequestAndPreserveUnownedRotations() {
        let direct = makeSubjects()
        let guarded = makeSubjects()
        let shadowRotation = simd_quatf(angle: 0.31, axis: [0, 1, 0])
        let emphasisRotation = simd_quatf(angle: -0.24, axis: [1, 0, 0])
        for subjects in [direct, guarded] {
            subjects.shadow.orientation = shadowRotation
            subjects.emphasis.orientation = emphasisRotation
        }
        let forward = Array(0..<128)
        let reverse = Array(forward.reversed())
        for frame in forward + reverse + [0, 110, 3, 127, 0] {
            let desired = state(frame: frame)
            writeDirect(desired, to: direct)
            writeGuarded(desired, to: guarded)
            assertState(direct, equals: desired)
            assertState(guarded, equals: desired)
            XCTAssertEqual(guarded.ball.transform, direct.ball.transform)
            XCTAssertEqual(guarded.shadow.transform, direct.shadow.transform)
            XCTAssertEqual(guarded.emphasis.transform, direct.emphasis.transform)
            XCTAssertEqual(guarded.shadow.orientation.vector, shadowRotation.vector)
            XCTAssertEqual(guarded.emphasis.orientation.vector, emphasisRotation.vector)
            // Both hierarchies have the same rotated/nonuniformly scaled parent.
            XCTAssertEqual(guarded.ball.convert(position: .zero, to: nil),
                           direct.ball.convert(position: .zero, to: nil))
        }
    }

    func testGuardsRepairExternalEditsAndAcceptOnlyExactQuaternionSignEquivalence() {
        let subjects = makeSubjects()
        let desired = state(frame: 8)
        writeDirect(desired, to: subjects)
        for entity in [subjects.ball, subjects.shadow, subjects.emphasis] {
            entity.position += [0.0001, 0.0001, 0.0001]
            entity.scale += [0.0001, 0.0001, 0.0001]
            entity.isEnabled.toggle()
        }
        subjects.ball.orientation = simd_quatf(angle: 0.0001, axis: [1, 0, 0]) * desired.rotation
        writeGuarded(desired, to: subjects)
        assertState(subjects, equals: desired)

        // A sign-equivalent unit quaternion must not trigger a setter solely
        // to restore its representation. A genuinely tiny turn still must.
        subjects.ball.orientation = simd_quatf(vector: -desired.rotation.vector)
        let signedRepresentation = subjects.ball.orientation.vector
        XCTAssertEqual(signedRepresentation, -desired.rotation.vector)
        writeGuarded(desired, to: subjects)
        XCTAssertEqual(subjects.ball.orientation.vector, signedRepresentation)
        XCTAssertEqual(subjects.ball.orientation.act([0, 0, 1]), desired.rotation.act([0, 0, 1]))

        subjects.ball.orientation = simd_quatf(angle: 0.00001, axis: [0, 1, 0]) * desired.rotation
        XCTAssertNotEqual(subjects.ball.orientation.vector, desired.rotation.vector)
        writeGuarded(desired, to: subjects)
        XCTAssertEqual(subjects.ball.orientation.vector, desired.rotation.vector)
        assertState(subjects, equals: desired)
    }

    private func makeSubjects() -> Subjects {
        let parent = Entity()
        parent.transform = Transform(scale: [0.025, 0.04, 0.03],
                                     rotation: simd_quatf(angle: 0.43, axis: [0, 1, 0]),
                                     translation: [1, 0.7, -2])
        let mesh = MeshResource.generateSphere(radius: 0.11)
        let ball = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let shadow = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .black)])
        let emphasis = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .cyan)])
        parent.addChild(ball)
        parent.addChild(shadow)
        parent.addChild(emphasis)
        return Subjects(parent: parent, ball: ball, shadow: shadow, emphasis: emphasis)
    }

    private func state(frame: Int) -> DesiredState {
        let progress = Float(frame) / 127
        let x = -12 + progress * 24
        let z = 7 - progress * 14
        let height = 0.11 + abs(sin(progress * .pi * 2)) * 1.4
        let scale: Float = frame.isMultiple(of: 5) ? 1.8 : 1
        let spread = 1 + min(max(height - 0.11, 0) * 0.16, 0.65)
        return DesiredState(
            position: [x, height + 0.11 * (scale - 1), z],
            rotation: simd_quatf(angle: progress * .pi * 2, axis: [1, 0, 0]),
            ballScale: SIMD3<Float>(repeating: scale),
            shadowPosition: [x, 0.006, z], shadowScale: [scale * spread, 1, scale * spread * 0.74],
            emphasisPosition: [x, 0.012, z], emphasisScale: SIMD3<Float>(repeating: frame.isMultiple(of: 3) ? 3.2 : scale),
            shown: !frame.isMultiple(of: 7), emphasized: !frame.isMultiple(of: 11)
        )
    }

    @inline(never)
    private func writeDirect(_ state: DesiredState, to subjects: Subjects) {
        subjects.ball.position = state.position
        subjects.ball.orientation = state.rotation
        subjects.ball.scale = state.ballScale
        subjects.ball.isEnabled = state.shown
        subjects.shadow.position = state.shadowPosition
        subjects.shadow.scale = state.shadowScale
        subjects.shadow.isEnabled = state.shown
        subjects.emphasis.position = state.emphasisPosition
        subjects.emphasis.scale = state.emphasisScale
        subjects.emphasis.isEnabled = state.shown && state.emphasized
    }

    @inline(never)
    private func writeGuarded(_ state: DesiredState, to subjects: Subjects) {
        if subjects.ball.position != state.position { subjects.ball.position = state.position }
        let actual = subjects.ball.orientation.vector
        if actual != state.rotation.vector && actual != -state.rotation.vector {
            subjects.ball.orientation = state.rotation
        }
        if subjects.ball.scale != state.ballScale { subjects.ball.scale = state.ballScale }
        if subjects.ball.isEnabled != state.shown { subjects.ball.isEnabled = state.shown }
        if subjects.shadow.position != state.shadowPosition { subjects.shadow.position = state.shadowPosition }
        if subjects.shadow.scale != state.shadowScale { subjects.shadow.scale = state.shadowScale }
        if subjects.shadow.isEnabled != state.shown { subjects.shadow.isEnabled = state.shown }
        if subjects.emphasis.position != state.emphasisPosition { subjects.emphasis.position = state.emphasisPosition }
        if subjects.emphasis.scale != state.emphasisScale { subjects.emphasis.scale = state.emphasisScale }
        let emphasized = state.shown && state.emphasized
        if subjects.emphasis.isEnabled != emphasized { subjects.emphasis.isEnabled = emphasized }
    }

    @inline(never)
    private func timeDirect(_ subjects: Subjects, states: [DesiredState], requests: Int) -> UInt64 {
        let started = DispatchTime.now().uptimeNanoseconds
        for request in 1...requests { writeDirect(states[request & 127], to: subjects) }
        return DispatchTime.now().uptimeNanoseconds &- started
    }

    @inline(never)
    private func timeGuarded(_ subjects: Subjects, states: [DesiredState], requests: Int) -> UInt64 {
        let started = DispatchTime.now().uptimeNanoseconds
        for request in 1...requests { writeGuarded(states[request & 127], to: subjects) }
        return DispatchTime.now().uptimeNanoseconds &- started
    }

    private func assertState(_ subjects: Subjects, equals expected: DesiredState,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(subjects.ball.position, expected.position, file: file, line: line)
        let actual = subjects.ball.orientation.vector
        XCTAssertTrue(actual == expected.rotation.vector || actual == -expected.rotation.vector, file: file, line: line)
        XCTAssertEqual(subjects.ball.scale, expected.ballScale, file: file, line: line)
        XCTAssertEqual(subjects.ball.isEnabled, expected.shown, file: file, line: line)
        XCTAssertEqual(subjects.shadow.position, expected.shadowPosition, file: file, line: line)
        XCTAssertEqual(subjects.shadow.scale, expected.shadowScale, file: file, line: line)
        XCTAssertEqual(subjects.shadow.isEnabled, expected.shown, file: file, line: line)
        XCTAssertEqual(subjects.emphasis.position, expected.emphasisPosition, file: file, line: line)
        XCTAssertEqual(subjects.emphasis.scale, expected.emphasisScale, file: file, line: line)
        XCTAssertEqual(subjects.emphasis.isEnabled, expected.shown && expected.emphasized, file: file, line: line)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) * 0.5
    }
}
