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
        let environment = ProcessInfo.processInfo.environment
        let selectedID = environment["REPLAYXI_EXPORT_STUDY"]
        let exportsAllRigs = environment["REPLAYXI_EXPORT_ALL_RIGS"] == "1"
        // High-detail exports are deliberately opt-in and limited to one study.
        // Ordinary suite runs retain the five-study, 10 Hz contact-actor receipt.
        if exportsAllRigs {
            _ = try XCTUnwrap(selectedID, "All-rig export requires REPLAYXI_EXPORT_STUDY")
        }
        let scenarios: [ReplayScenario]
        if let selectedID {
            scenarios = [try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == selectedID },
                                      "Unknown current reference study: \(selectedID)")]
        } else {
            scenarios = FootballReferenceScenarios.all
        }
        var studies: [[String: Any]] = []
        for scenario in scenarios {
            let reference = try XCTUnwrap(ReplayReferenceLibrary.reference(for: scenario.id))
            let planned = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: planned)
            XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
            XCTAssertEqual(recording.touches.count, planned.count, scenario.id)
            let detailedTimes = exportsAllRigs ? sampleTimes(duration: scenario.duration, frequency: 20,
                                                            contacts: recording.touches.map(\.time)) : []
            XCTAssertLessThanOrEqual(detailedTimes.count, 700, "Bound the optional offline export")
            let rosterPoses = Dictionary(uniqueKeysWithValues: detailedTimes.map { time in
                (time, Dictionary(uniqueKeysWithValues: scenario.players.map {
                    ($0.id, $0.presentationPose(at: time))
                }))
            })
            let players: [[String: Any]] = scenario.players.map { player in
                // Bone samples at 20 Hz do not all fall on the 30 Hz root grid.
                // Include both so Blender never interpolates a different root
                // or heading at an exact exported native-pose instant.
                let times = sampleTimes(duration: scenario.duration, frequency: 30,
                                        contacts: recording.touches.map(\.time) + detailedTimes)
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
                var result: [String: Any] = ["time": touch.time, "playerID": touch.playerID, "kind": touch.kind.rawValue,
                 "leg": touch.kickingLeg.rawValue,
                 "position": ["x": touch.position.x, "y": touch.position.y, "z": touch.position.z],
                 "outgoingDirection": ["x": touch.outgoingVelocity.x, "y": touch.outgoingVelocity.y,
                                       "z": touch.outgoingVelocity.z]]
                if let support = touch.headerSupportLeg { result["headerSupportLeg"] = support.rawValue }
                return result
            }
            let rigPoses = try scenario.players.filter { player in
                exportsAllRigs || recording.touches.contains { $0.playerID == player.id }
            }.map { try poseFrames(for: $0, scenario: scenario, recording: recording,
                                   detailedTimes: detailedTimes, rosterPoses: rosterPoses,
                                   exportsAllRigs: exportsAllRigs) }
            XCTAssertEqual(rigPoses.count, exportsAllRigs ? 22 : Set(recording.touches.map(\.playerID)).count)
            studies.append(["id": scenario.id, "title": scenario.title, "duration": scenario.duration,
                "source": ["matchTitle": reference.matchTitle, "url": reference.sourceURL.absoluteString,
                           "windowStartSeconds": reference.startSeconds, "windowEndSeconds": reference.endSeconds,
                           "notes": reference.reconstructionNote],
                "players": players, "ball": ["keyframes": ball, "source": "native-physics-recording"],
                "contacts": contacts,
                "rigPoses": rigPoses,
                "rigSampling": ["scope": exportsAllRigs ? "all-players" : "contact-players",
                                "frequencyHz": exportsAllRigs ? 20 : 10,
                                "includesExactContacts": true, "tacticalAttention": exportsAllRigs],
                "limitations": "Authored reconstruction. Body motion and unseen player positions are inferred; no measured tracking or match mocap."])
        }
        XCTAssertEqual(studies.count, selectedID == nil ? 5 : 1)
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "coordinateSystem": "pitch-metres-x-width-z-length", "studies": studies], options: [.sortedKeys])
        XCTAssertLessThanOrEqual(data.count, 40 * 1024 * 1024, "Keep the audited Blender parser's 40 MB cap")
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = selectedID.map { "ReplayXI-\($0)-\(exportsAllRigs ? "All-Native-Rigs" : "Reference").json" }
            ?? "ReplayXI-Five-Reference-Studies.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    private func poseFrames(for player: PlayerTrack, scenario: ReplayScenario,
                            recording: ReplayNativeBallPhysics.Recording,
                            detailedTimes: [TimeInterval],
                            rosterPoses: [TimeInterval: [String: PlayerPose]],
                            exportsAllRigs: Bool) throws -> [String: Any] {
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        let actor = Entity()
        actor.addChild(skin.root)
        let shots = ReplayFootballShotTimeline(touches: recording.touches, players: scenario.players)
        let cues = recording.touches.filter { $0.playerID == player.id }.compactMap { touch -> ReplayAthleteInteractionCue? in
            guard let kind = ReplayAthleteInteractionCue.Kind(rawValue: touch.kind.rawValue) else { return nil }
            return .init(playerID: player.id, kind: kind, contactTime: touch.time,
                         startTime: touch.time - 0.32, endTime: touch.time + 0.42,
                         kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
                         outgoingDirectionWorld: touch.outgoingVelocity,
                         headerSupportLeg: touch.headerSupportLeg)
        }
        // Include actual contact instants even when they fall between 10 Hz samples.
        let times = exportsAllRigs ? detailedTimes : sampleTimes(duration: scenario.duration, frequency: 10,
                                                                contacts: cues.map(\.contactTime))
        var frames: [[String: Any]] = []
        var vectors: [[Float]] = []
        var vectorIndices: [[UInt32]: Int] = [:]
        func encoded(_ rows: [[Float]]) -> Any {
            guard exportsAllRigs else { return rows }
            return rows.map { row in
                // Exact Float bit patterns, no rounding or quaternion sign
                // changes. Repeated rest/finger/scale channels share one row.
                let key = row.map(\.bitPattern)
                if let index = vectorIndices[key] { return index }
                let index = vectors.count
                vectors.append(row)
                vectorIndices[key] = index
                return index
            }
        }
        for time in times {
            let presented = rosterPoses[time]?[player.id] ?? player.presentationPose(at: time)
            actor.position = [presented.position.x, 0, presented.position.z]
            actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
            let cue = cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
            let ball = recording.sample(at: time).position
            let lookTarget = exportsAllRigs ? ReplayAthleteTacticalAttention.target(
                for: player, at: time, pose: presented, ball: ball,
                players: scenario.players, poses: rosterPoses[time] ?? [:], contacts: cues) : ball
            let keeper = ReplayGoalkeeperReadiness.sample(track: player, at: time,
                presentationPose: presented, ballPosition: ball,
                shot: shots.latestOpposingShot(for: player, at: time),
                actionInfluence: ReplayAthleteInteractionPose.sample(cue: cue, at: time,
                    track: player, presentationPose: presented)?.influence ?? 0,
                enabled: player.isGoalkeeper)
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                     lookTarget: lookTarget, ballAction: nil,
                                     interaction: cue, presentationPose: presented,
                                     goalkeeperReadiness: keeper))
            frames.append(["time": time, "translations": encoded(skin.pose.translations.map { [$0.x, $0.y, $0.z] }),
                "rotations": encoded(skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] }),
                "scales": encoded(skin.pose.scales.map { [$0.x, $0.y, $0.z] })])
        }
        var result: [String: Any] = ["playerID": player.id, "source": "native-rig-pose-samples",
                "groundOffset": -skin.motion.geometry.restMinY,
                "jointNames": skin.motion.joints.map(\.name),
                "sourceJointNames": skin.motion.joints.map(\.sourceName), "frames": frames]
        if exportsAllRigs {
            result["transformEncoding"] = "float32-vector-table-v1"
            // Float -> JSON's promoted decimal representation can exceed 40 MB
            // for 22 rigs. Eight hex digits retain every original Float bit,
            // including signed zero, without rounding or changing transforms.
            result["vectorTable"] = vectors.map { row in
                row.map { value in
                    let hex = String(value.bitPattern, radix: 16)
                    return String(repeating: "0", count: 8 - hex.count) + hex
                }.joined()
            }
            result["presentation"] = "native-near-rig-with-tactical-attention; all players exported offline, not runtime LOD admission"
        }
        return result
    }

    private func sampleTimes(duration: TimeInterval, frequency: Double,
                             contacts: [TimeInterval]) -> [TimeInterval] {
        Set((0...Int(ceil(duration * frequency))).map {
            min(duration, Double($0) / frequency)
        } + contacts).sorted()
    }
}
