import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Blender receives precisely the app's player paths and admitted ball physics,
/// not a second, unrelated reconstruction. The export is an optional test receipt.
@MainActor
final class ReplayReferenceBlenderExportTests: XCTestCase {
    func testExportFivePlayableReferenceStudies() async throws {
        defer {
            ReplayNativeBallPhysics.resetCacheForTesting()
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        var studies: [[String: Any]] = []
        for scenario in FootballReferenceScenarios.all {
            let reference = try XCTUnwrap(ReplayReferenceLibrary.reference(for: scenario.id))
            let planned = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: planned)
            XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
            XCTAssertEqual(recording.touches.count, planned.count, scenario.id)
            let players: [[String: Any]] = scenario.players.map { player in
                let times = Set((0...Int(ceil(scenario.duration * 30))).map {
                    min(scenario.duration, Double($0) / 30)
                } + recording.touches.map(\.time)).sorted()
                let samples: [[String: Any]] = times.map { time in
                    let pose = player.presentationPose(at: time)
                    return ["time": time, "position": ["x": pose.position.x, "z": pose.position.z],
                            "facingDegrees": pose.facingDegrees]
                }
                return ["id": player.id, "displayName": player.displayName,
                        "shirtNumber": player.shirtNumber, "team": player.team.rawValue,
                        "isGoalkeeper": player.isGoalkeeper, "role": player.role,
                        "keyframes": samples,
                        "evidence": ["origin": "authored", "sourceVisibility": "unknown",
                                     "confidence": NSNull(), "measured3D": false]]
            }
            let ball: [[String: Any]] = recording.samples.map { sample in
                ["time": sample.time, "position": ["x": sample.position.x, "z": sample.position.z],
                 "height": sample.position.y,
                 "rotation": [sample.orientation.imag.x, sample.orientation.imag.y,
                              sample.orientation.imag.z, sample.orientation.real]]
            }
            let contacts: [[String: Any]] = recording.touches.map { touch in
                ["time": touch.time, "playerID": touch.playerID, "kind": touch.kind.rawValue,
                 "leg": touch.kickingLeg.rawValue,
                 "position": ["x": touch.position.x, "y": touch.position.y, "z": touch.position.z],
                 "outgoingDirection": ["x": touch.outgoingVelocity.x, "y": touch.outgoingVelocity.y,
                                       "z": touch.outgoingVelocity.z]]
            }
            let rigPoses = try scenario.players.filter { player in
                recording.touches.contains { $0.playerID == player.id }
            }.map { try poseFrames(for: $0, scenario: scenario, recording: recording) }
            studies.append(["id": scenario.id, "title": scenario.title, "duration": scenario.duration,
                "source": ["matchTitle": reference.matchTitle, "url": reference.sourceURL.absoluteString,
                           "windowStartSeconds": reference.startSeconds, "windowEndSeconds": reference.endSeconds,
                           "notes": reference.reconstructionNote],
                "players": players, "ball": ["keyframes": ball, "source": "native-physics-recording"],
                "contacts": contacts,
                "rigPoses": rigPoses,
                "limitations": "Authored reconstruction. Body motion and unseen player positions are inferred; no measured tracking or match mocap."])
        }
        XCTAssertEqual(studies.count, 5)
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "coordinateSystem": "pitch-metres-x-width-z-length", "studies": studies], options: [.sortedKeys])
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Five-Reference-Studies.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    private func poseFrames(for player: PlayerTrack, scenario: ReplayScenario,
                            recording: ReplayNativeBallPhysics.Recording) throws -> [String: Any] {
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        let actor = Entity()
        actor.addChild(skin.root)
        let cues = recording.touches.filter { $0.playerID == player.id }.compactMap { touch -> ReplayAthleteInteractionCue? in
            guard let kind = ReplayAthleteInteractionCue.Kind(rawValue: touch.kind.rawValue) else { return nil }
            return .init(playerID: player.id, kind: kind, contactTime: touch.time,
                         startTime: touch.time - 0.32, endTime: touch.time + 0.42,
                         kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
                         outgoingDirectionWorld: touch.outgoingVelocity)
        }
        // Include actual contact instants even when they fall between 10 Hz samples.
        let times = Set((0...Int(ceil(scenario.duration * 10))).map {
            min(scenario.duration, Double($0) / 10)
        } + cues.map(\.contactTime)).sorted()
        var frames: [[String: Any]] = []
        for time in times {
            let presented = player.presentationPose(at: time)
            actor.position = [presented.position.x, 0, presented.position.z]
            actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
            let cue = cues.filter { time >= $0.startTime && time <= $0.endTime }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                     lookTarget: recording.sample(at: time).position, ballAction: nil,
                                     interaction: cue, presentationPose: presented))
            frames.append(["time": time, "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
                "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] }])
        }
        return ["playerID": player.id, "source": "native-rig-pose-samples",
                "groundOffset": -skin.motion.geometry.restMinY,
                "jointNames": skin.motion.joints.map(\.name),
                "sourceJointNames": skin.motion.joints.map(\.sourceName), "frames": frames]
    }
}
