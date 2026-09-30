import Dispatch
import RealityKit
import XCTest
@testable import ReplayXI

/// Diagnostic update-path comparison only; timings are observations, not gates.
@MainActor
final class PlaybackPlayerLabelPerf162Tests: XCTestCase {
    private struct LabelState: Equatable {
        let name: String
        let transform: Transform
        let enabled: Bool
        let children: [ChildState]
    }

    private struct ChildState: Equatable {
        let name: String
        let transform: Transform
        let enabled: Bool
    }

    private struct PathStats: Codable {
        var medianNanosecondsPerUpdate: UInt64
        var indexedLookups: Int
        var fallbackInspections: Int
        var visitedLabels: Int
    }

    private struct PhaseReport: Codable {
        let phase: String
        let repeats: Int
        let samplesPerRepeat: Int
        let indexed: PathStats
        let oldFallback: PathStats
    }

    private struct Report: Codable {
        let players: Int
        let scope: String
        let phases: [PhaseReport]
    }

    private struct Measurements {
        var durations: [UInt64] = []
        var indexedLookups = 0
        var fallbackInspections = 0
        var visitedLabels = 0

        mutating func record(duration: UInt64, work: PlaybackSpatialLabels.UpdateWork) {
            durations.append(duration)
            indexedLookups += work.playerLabelIndexedLookups
            fallbackInspections += work.playerLabelFallbackInspections
            visitedLabels += work.visitedPlayerLabels
        }

        func report() -> PathStats {
            let sorted = durations.sorted()
            let middle = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2)
                ? UInt64((Double(sorted[middle - 1]) + Double(sorted[middle])) / 2)
                : sorted[middle]
            return PathStats(medianNanosecondsPerUpdate: median,
                indexedLookups: indexedLookups,
                fallbackInspections: fallbackInspections,
                visitedLabels: visitedLabels)
        }
    }

    func testIndexedAndOldFallbackUpdatesMatchAcrossPlaybackPhases() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        XCTAssertEqual(scenario.players.count, 22)
        let indexedRoot = Entity()
        let indexedLabels = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        indexedRoot.addChild(indexedLabels)

        // Rebuild the same hierarchy without its construction-time index.
        // The old fallback path then performs its original first-match scan.
        let fallbackRoot = Entity()
        let fallbackLabels = Entity()
        fallbackLabels.name = "player-labels-root"
        for label in indexedLabels.children {
            fallbackLabels.addChild(label.clone(recursive: true))
        }
        fallbackRoot.addChild(fallbackLabels)
        XCTAssertEqual(indexedLabels.children.count, fallbackLabels.children.count)

        let sampleCount = 200
        let repeats = 5
        let forward = (0..<sampleCount).map { 4.0 + Double($0) / 30.0 }
        let reverse = forward.reversed()
        let phases: [(String, [TimeInterval])] = [
            ("paused", Array(repeating: 4.0, count: sampleCount)),
            ("forward", forward),
            ("reverse", Array(reverse))
        ]
        var phaseReports: [PhaseReport] = []

        for (phaseName, times) in phases {
            var indexed = Measurements()
            var fallback = Measurements()
            for repeatIndex in 0..<repeats {
                for (sampleIndex, time) in times.enumerated() {
                    let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
                        ($0.id, $0.presentationPose(at: time))
                    })
                    let indexedFirst = (repeatIndex + sampleIndex).isMultiple(of: 2)
                    if indexedFirst {
                        update(indexedRoot, scenario: scenario, poses: poses,
                               into: &indexed)
                        update(fallbackRoot, scenario: scenario, poses: poses,
                               into: &fallback)
                    } else {
                        update(fallbackRoot, scenario: scenario, poses: poses,
                               into: &fallback)
                        update(indexedRoot, scenario: scenario, poses: poses,
                               into: &indexed)
                    }
                    XCTAssertEqual(snapshot(indexedLabels), snapshot(fallbackLabels),
                        "Output mismatch in \(phaseName), repeat \(repeatIndex), sample \(sampleIndex)")
                }
            }
            let updates = repeats * sampleCount
            XCTAssertEqual(indexed.visitedLabels, updates * scenario.players.count)
            XCTAssertEqual(fallback.visitedLabels, updates * scenario.players.count)
            XCTAssertEqual(indexed.indexedLookups, updates * scenario.players.count)
            XCTAssertEqual(indexed.fallbackInspections, 0)
            XCTAssertEqual(fallback.indexedLookups, 0)
            XCTAssertEqual(fallback.fallbackInspections, updates * (scenario.players.count * (scenario.players.count + 1) / 2))
            phaseReports.append(PhaseReport(phase: phaseName, repeats: repeats,
                samplesPerRepeat: sampleCount, indexed: indexed.report(),
                oldFallback: fallback.report()))
        }

        let report = Report(players: scenario.players.count,
            scope: "Five repeats of 200 paused, forward, and reverse updates per path. Per-call DispatchTime measurements include clock overhead; matched paths alternate call order and verify exact label and child transforms/enabled states after each pair. Structural counters count requested app-side lookups only. No speed threshold, renderer/GPU work, allocations, headset FPS, or timing claim.",
            phases: phaseReports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report),
            uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-PlayerLabelPerf162-A-B.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func update(_ root: Entity, scenario: ReplayScenario,
                        poses: [String: PlayerPose], into measurements: inout Measurements) {
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        let start = DispatchTime.now().uptimeNanoseconds
        PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario,
            posesByPlayerID: poses, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID)
        let duration = DispatchTime.now().uptimeNanoseconds - start
        measurements.record(duration: duration, work: PlaybackSpatialLabels.updateWork)
    }

    private func snapshot(_ root: Entity) -> [LabelState] {
        root.children.map { label in
            LabelState(name: label.name, transform: label.transform,
                enabled: label.isEnabled,
                children: label.children.map { child in
                    ChildState(name: child.name, transform: child.transform,
                        enabled: child.isEnabled)
                })
        }
    }
}
