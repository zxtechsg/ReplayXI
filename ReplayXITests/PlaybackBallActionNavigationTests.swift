import simd
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackBallActionNavigationTests: XCTestCase {
    func testAllThreeStudiesNavigateRecordedTimesRatherThanAuthoredBeatTimes() throws {
        for scenario in FootballReferenceScenarios.all {
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let touches = plan.map { touch($0.time + 0.037, $0.playerID, $0.kind) }
            let source = makeSource(scenario, touches: touches)
            var time = 0.0
            for (planned, actual) in zip(plan, touches) {
                let next = try XCTUnwrap(PlaybackBallActionNavigation.destination(.next,
                    source: source, scenario: scenario, at: time))
                XCTAssertEqual(next.time, actual.time)
                XCTAssertNotEqual(next.time, planned.time)
                XCTAssertEqual(next.playerID, actual.playerID)
                XCTAssertEqual(next.kind, actual.kind)
                time = next.time
            }
            XCTAssertNil(PlaybackBallActionNavigation.destination(.next,
                source: source, scenario: scenario, at: time))
            for actual in touches.dropLast().reversed() {
                let previous = try XCTUnwrap(PlaybackBallActionNavigation.destination(.previous,
                    source: source, scenario: scenario, at: time))
                XCTAssertEqual(previous.time, actual.time)
                time = previous.time
            }
            XCTAssertNil(PlaybackBallActionNavigation.destination(.previous,
                source: source, scenario: scenario, at: time))
        }
    }

    func testCloseContactsRemainReachableAndNoBoundaryWrapOccurs() {
        let scenario = FootballReferenceScenarios.all[0]
        let source = makeSource(scenario, touches: [touch(0, "arg-26"), touch(1, "arg-10"), touch(1.05, "arg-9")])
        XCTAssertNil(PlaybackBallActionNavigation.destination(.previous, source: source, scenario: scenario, at: 0))
        XCTAssertEqual(PlaybackBallActionNavigation.destination(.next, source: source, scenario: scenario, at: 1)?.time, 1.05)
        XCTAssertEqual(PlaybackBallActionNavigation.destination(.previous, source: source, scenario: scenario, at: 1.05)?.time, 1)
        XCTAssertEqual(PlaybackBallActionNavigation.destination(.previous, source: source, scenario: scenario, at: 1)?.time, 0)
        XCTAssertNil(PlaybackBallActionNavigation.destination(.next, source: source, scenario: scenario, at: scenario.duration))
    }

    func testMalformedTouchesAndRoutineDribblesAreSkippedWithoutSortingInput() {
        let scenario = FootballReferenceScenarios.all[0]
        let source = makeSource(scenario, touches: [
            touch(3, "arg-11", .shot), touch(.nan, "arg-10"), touch(-1, "arg-10"),
            touch(.infinity, "arg-10"), touch(scenario.duration + 1, "arg-10"),
            touch(0.5, "unknown"), touch(0.4, "arg-10", .dribbleTouch), touch(1, "arg-10", .header)
        ])
        let next = PlaybackBallActionNavigation.destination(.next, source: source, scenario: scenario, at: 0)
        XCTAssertEqual(next?.time, 1)
        XCTAssertEqual(next?.kind, .header)
        XCTAssertEqual(PlaybackBallActionNavigation.destination(.previous,
            source: source, scenario: scenario, at: 2)?.time, 1)
        for invalid in [Double.nan, .infinity, -1, scenario.duration + 1] {
            XCTAssertNil(PlaybackBallActionNavigation.destination(.next, source: source, scenario: scenario, at: invalid))
        }
    }

    func testPreparationFailureStaleSourceAndLegacyScenarioHaveNoNativeDestination() {
        let scenario = FootballReferenceScenarios.all[0]
        let source = makeSource(scenario, touches: [touch(1, "arg-10")])
        XCTAssertNil(PlaybackBallActionNavigation.destination(.next, source: nil, scenario: scenario, at: 0))
        XCTAssertNil(PlaybackBallActionNavigation.destination(.next, source: source,
            scenario: FootballReferenceScenarios.all[1], at: 0))
        XCTAssertNil(PlaybackBallActionNavigation.destination(.next, source: source, scenario: DemoScenarios.all[0], at: 0))
        let incomplete = makeSource(scenario, touches: [touch(1, "arg-10")], missed: 1)
        XCTAssertNil(PlaybackBallActionNavigation.destination(.next, source: incomplete, scenario: scenario, at: 0))
    }

    func testJumpPausesAtExactContactAndPreservesPOVMarksRateAndUndoHistory() throws {
        let store = makeStore()
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -3, z: 10))
        _ = try XCTUnwrap(store.registerPitchTap(.init(x: 4, z: 18)))
        store.openLocalPlayerPOV("arg-10")
        let marks = store.marks
        let rate = store.playbackRate
        let canUndo = store.canUndoAnnotationEdit
        store.setPlaying(true, broadcast: false)
        let source = makeSource(store.selectedScenario, touches: [touch(1.137, "arg-9", .pass)])
        let target = try XCTUnwrap(PlaybackBallActionNavigation.jump(.next, source: source, in: store))
        XCTAssertEqual(target.time, 1.137)
        XCTAssertEqual(store.playhead, 1.137)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.activePerspectiveID, "arg-10")
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.marks, marks)
        XCTAssertEqual(store.playbackRate, rate)
        XCTAssertEqual(store.canUndoAnnotationEdit, canUndo)
        XCTAssertEqual(store.makeSavedReviewState().marks, marks)
        XCTAssertTrue(store.statusMessage.contains("#9"))
        XCTAssertTrue(store.statusMessage.contains("Pass"))
    }

    func testActiveDrawingScrubAndCurveEditBlockNavigationWithoutMutation() throws {
        let store = makeStore()
        let source = makeSource(store.selectedScenario, touches: [touch(1.1, "arg-10")])
        store.beginDrawing(.arc)
        assertBlocked(source, in: store)
        _ = store.registerPitchTap(.init(x: -3, z: 10))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 4, z: 18)))
        XCTAssertTrue(store.beginTimelineScrub())
        assertBlocked(source, in: store)
        store.cancelTimelineScrub()
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: token, curve: .init(bend: 2, lift: 1)))
        assertBlocked(source, in: store)
        XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: token))
        XCTAssertNotNil(PlaybackBallActionNavigation.jump(.next, source: source, in: store))
    }

    func testLateButtonCallbackCannotJumpAfterScenarioChanges() {
        let store = makeStore()
        let stale = makeSource(store.selectedScenario, touches: [touch(1.1, "arg-10")])
        store.selectScenario(id: FootballReferenceScenarios.all[1].id)
        assertBlocked(stale, in: store)
        assertBlocked(nil, in: store)
    }

    private func assertBlocked(_ source: PlaybackBallActionNavigation.Source?, in store: ReplayStore,
                               file: StaticString = #filePath, line: UInt = #line) {
        let before = store.makeSnapshot()
        let status = store.statusMessage
        XCTAssertNil(PlaybackBallActionNavigation.jump(.next, source: source, in: store), file: file, line: line)
        XCTAssertEqual(store.makeSnapshot(), before, file: file, line: line)
        XCTAssertEqual(store.statusMessage, status, file: file, line: line)
    }

    private func makeStore() -> ReplayStore {
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.prepareForLocalExperience()
        return store
    }

    private func touch(_ time: Double, _ playerID: String,
                       _ kind: ReplayNativeBallPhysics.TouchKind = .pass) -> ReplayNativeBallPhysics.Touch {
        .init(time: time, playerID: playerID, position: .zero,
              outgoingVelocity: [0, 0, 1], kind: kind, kickingLeg: .right)
    }

    private func makeSource(_ scenario: ReplayScenario, touches: [ReplayNativeBallPhysics.Touch],
                            missed: Int = 0) -> PlaybackBallActionNavigation.Source {
        let samples = [0.0, scenario.duration].map {
            ReplayNativeBallPhysics.Sample(time: $0, position: [0, 0.11, 0],
                orientation: simd_quatf(real: 1, imag: .zero), velocity: .zero, angularVelocity: .zero)
        }
        return .init(scenarioID: scenario.id,
                     recording: .init(samples: samples, touches: touches, missedTouchCount: missed))
    }
}
