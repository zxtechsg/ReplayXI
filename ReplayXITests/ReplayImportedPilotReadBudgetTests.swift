import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Count setting reads, not elapsed time or headset FPS. The actual prepared
/// scene must retain its model policy while resolving the pilot once per call.
@MainActor
final class ReplayImportedPilotReadBudgetTests: XCTestCase {
    private var roots: [Entity] = []
    private var previousDefault: Any?

    override func setUp() {
        super.setUp()
        previousDefault = UserDefaults.standard.object(forKey: ReplayImportedAthleteFeatureGate.userDefaultsKey)
        UserDefaults.standard.set(false, forKey: ReplayImportedAthleteFeatureGate.userDefaultsKey)
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayImportedAthleteFeatureGate.resetReadCountForTesting()
    }

    override func tearDown() {
        for root in roots {
            for child in Array(root.children) { child.removeFromParent() }
        }
        roots.removeAll()
        if let previousDefault {
            UserDefaults.standard.set(previousDefault, forKey: ReplayImportedAthleteFeatureGate.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ReplayImportedAthleteFeatureGate.userDefaultsKey)
        }
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayImportedAthleteFeatureGate.resetReadCountForTesting()
        super.tearDown()
    }

    private func prepare(low: Bool, kind: ExperienceKind = .squadReplay) throws -> (ReplayScenario, Entity) {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled,
                      "An explicit environment override enables the separate imported pilot")
        try ReplaySkinnedAthleteProvider.prewarm()
        if low { try ReplaySkinnedAthleteProvider.prewarmLowDetail() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: kind))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        roots.append(root)
        return (scenario, root)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double,
                        view: ReplayViewMode) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }

    private func assertWarmReadBudget(low: Bool, kind: ExperienceKind = .squadReplay,
                                      views: [ReplayViewMode], expectedNear: Int,
                                      expectedLow: Int) throws {
        let (scenario, root) = try prepare(low: low, kind: kind)
        let firstView = try XCTUnwrap(views.first)
        update(root, scenario: scenario, time: 12, view: firstView)
        for (index, view) in views.enumerated() {
            let before = ReplayImportedAthleteFeatureGate.readCountForTesting
            update(root, scenario: scenario, time: index.isMultiple(of: 2) ? 12 : 13.6, view: view)
            XCTAssertEqual(ReplayImportedAthleteFeatureGate.readCountForTesting - before, 1,
                           "Resolve the developer switch once, including reused skins: \(view)")
            let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            XCTAssertEqual(skins.values.filter { $0.detail == .near }.count, expectedNear)
            XCTAssertEqual(skins.values.filter { $0.detail == .lowDetail }.count, expectedLow)
            XCTAssertTrue(skins.values.allSatisfy { $0.root.isEnabled && $0.root.parent != nil })
        }
    }

    func testWarmNearOnlySceneReadsPilotOncePerUpdate() throws {
        try assertWarmReadBudget(low: false, views: [.tacticalTable, .touchline, .tacticalTable],
                                 expectedNear: 1, expectedLow: 0)
    }

    func testUnpreparedFallbackDoesNotReadPilotSetting() throws {
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isPrewarmed)
        let cases: [(ExperienceKind, [ReplayViewMode])] = [
            (.squadReplay, [.tacticalTable, .touchline, .firstPerson]),
            (.shapeLab, [.positional])
        ]
        for (kind, views) in cases {
            let scenario = try XCTUnwrap(DemoScenarios.scenario(for: kind))
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            roots.append(root)
            for view in views {
                let before = ReplayImportedAthleteFeatureGate.readCountForTesting
                update(root, scenario: scenario, time: 12, view: view)
                XCTAssertEqual(ReplayImportedAthleteFeatureGate.readCountForTesting, before,
                               "The unprepared procedural fallback needs no pilot setting")
                XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root).isEmpty)
            }
        }
    }

    func testWarmMixedSceneReadsPilotOncePerUpdate() throws {
        try assertWarmReadBudget(low: true, views: [.tacticalTable, .touchline, .tacticalTable],
                                 expectedNear: 1, expectedLow: 3)
    }

    func testWarmPOVReadsPilotOnceWithoutAdmittingLowSkins() throws {
        try assertWarmReadBudget(low: true, views: [.firstPerson, .firstPerson, .firstPerson],
                                 expectedNear: PitchSceneFactory.firstPersonDetailedRigLimit, expectedLow: 0)
    }

    func testWarmShapeReadsPilotOnceWithoutAdmittingLowSkins() throws {
        try assertWarmReadBudget(low: true, kind: .shapeLab,
                                 views: [.positional, .positional, .positional],
                                 expectedNear: 4, expectedLow: 0)
    }

    func testEverySceneCallSeesFreshDefaultsWithoutChangingOverridePrecedence() throws {
        let environment = ProcessInfo.processInfo.environment[ReplayImportedAthleteFeatureGate.environmentKey]
        let resolvesFalse = ReplayImportedAthleteFeatureGate.resolvedValue(
            environmentValue: environment, userDefaultsValue: false, debugDefault: false)
        let resolvesTrue = ReplayImportedAthleteFeatureGate.resolvedValue(
            environmentValue: environment, userDefaultsValue: true, debugDefault: false)
        try XCTSkipIf(resolvesFalse == resolvesTrue,
                      "A valid process override intentionally takes precedence over live Defaults")
        let (scenario, root) = try prepare(low: true)
        for enabled in [false, true, false] {
            UserDefaults.standard.set(enabled, forKey: ReplayImportedAthleteFeatureGate.userDefaultsKey)
            let before = ReplayImportedAthleteFeatureGate.readCountForTesting
            update(root, scenario: scenario, time: 12, view: .tacticalTable)
            XCTAssertEqual(ReplayImportedAthleteFeatureGate.readCountForTesting - before, 1)
            let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            XCTAssertEqual(skins.values.filter { $0.detail == .near }.count, 1)
            XCTAssertEqual(skins.values.filter { $0.detail == .lowDetail }.count, enabled ? 0 : 3)
            XCTAssertEqual(ReplayImportedAthleteFeatureGate.isEnabled, enabled,
                           "The per-scene snapshot must not become a process-wide value cache")
        }
    }
}
