import simd
import XCTest
@testable import ReplayXI

@MainActor
final class NativeReplaySceneAdmissionTests: XCTestCase {
    func testMatchingRequestRetainsExactRecordingForOnlyItsStudyAndRoom() {
        var admission = NativeReplaySceneAdmission()
        let room = UUID()
        let request = admission.begin(scenarioID: "study-a", roomID: room)
        let recording = makeRecording()
        XCTAssertNil(admission.recording(for: "study-a", roomID: room))
        XCTAssertFalse(admission.hasFailed(for: "study-a", roomID: room))
        XCTAssertTrue(admission.complete(recording, request: request,
            currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertTrue(admission.recording(for: "study-a", roomID: room) === recording)
        XCTAssertNil(admission.recording(for: "study-b", roomID: room))
        XCTAssertNil(admission.recording(for: "study-a", roomID: UUID()))
    }

    func testChangedStudyRejectsCompletionBeforeItsNextTaskEvenBegins() {
        var admission = NativeReplaySceneAdmission()
        let room = UUID()
        let previous = admission.begin(scenarioID: "study-a", roomID: room)
        XCTAssertFalse(admission.complete(makeRecording(), request: previous,
            currentScenarioID: "study-b", roomIsOwned: true))
        XCTAssertFalse(admission.fail(request: previous, currentScenarioID: "study-b", roomIsOwned: true))
        XCTAssertNil(admission.recording(for: "study-a", roomID: room))
        XCTAssertNil(admission.recording(for: "study-b", roomID: room))
        XCTAssertFalse(admission.hasFailed(for: "study-b", roomID: room))
    }

    func testSwitchAwayAndBackRejectsTheFirstRequestForTheSameStudy() {
        var admission = NativeReplaySceneAdmission()
        let room = UUID()
        let stale = admission.begin(scenarioID: "study-a", roomID: room)
        _ = admission.begin(scenarioID: "study-b", roomID: room)
        let current = admission.begin(scenarioID: "study-a", roomID: room)
        XCTAssertNotEqual(stale, current)
        XCTAssertFalse(admission.complete(makeRecording(), request: stale,
            currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertTrue(admission.complete(makeRecording(), request: current,
            currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertFalse(admission.fail(request: stale, currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertNotNil(admission.recording(for: "study-a", roomID: room))
        XCTAssertFalse(admission.hasFailed(for: "study-a", roomID: room))
    }

    func testFailedPreparationCanRetryWithoutAcceptingOldFailure() {
        var admission = NativeReplaySceneAdmission()
        let room = UUID()
        let first = admission.begin(scenarioID: "study-a", roomID: room)
        XCTAssertTrue(admission.fail(request: first, currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertTrue(admission.hasFailed(for: "study-a", roomID: room))
        let retry = admission.begin(scenarioID: "study-a", roomID: room)
        XCTAssertFalse(admission.hasFailed(for: "study-a", roomID: room))
        let recording = makeRecording()
        XCTAssertTrue(admission.complete(recording, request: retry,
            currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertFalse(admission.fail(request: first, currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertTrue(admission.recording(for: "study-a", roomID: room) === recording)
    }

    func testIncompleteNativeRecordingFailsClosedRatherThanAdmittingFallback() {
        for recording in [makeRecording(missedTouches: 1),
                          ReplayNativeBallPhysics.Recording(samples: [], touches: [], missedTouchCount: 0)] {
            var admission = NativeReplaySceneAdmission()
            let room = UUID()
            let request = admission.begin(scenarioID: "study-a", roomID: room)
            XCTAssertFalse(NativeReplaySceneAdmission.isUsable(recording))
            XCTAssertFalse(admission.complete(recording, request: request,
                currentScenarioID: "study-a", roomIsOwned: true))
            XCTAssertTrue(admission.hasFailed(for: "study-a", roomID: room))
            XCTAssertNil(admission.recording(for: "study-a", roomID: room))
        }
    }

    func testClosingRoomAndCancelledTaskCannotAdmitLateRecording() {
        var admission = NativeReplaySceneAdmission()
        let room = UUID()
        let request = admission.begin(scenarioID: "study-a", roomID: room)
        XCTAssertFalse(admission.complete(makeRecording(), request: request,
            currentScenarioID: "study-a", roomIsOwned: false))
        XCTAssertFalse(admission.fail(request: request, currentScenarioID: "study-a", roomIsOwned: false))
        admission.cancel()
        XCTAssertFalse(admission.complete(makeRecording(), request: request,
            currentScenarioID: "study-a", roomIsOwned: true))
        XCTAssertNil(admission.recording(for: "study-a", roomID: room))
        XCTAssertFalse(admission.hasFailed(for: "study-a", roomID: room))
    }

    func testRetryAndEveryScenarioIDHaveDistinctTaskKeys() {
        let initial = NativeReplaySceneAdmission.TaskID(scenarioID: "study-a", retry: 0)
        XCTAssertNotEqual(initial, .init(scenarioID: "study-b", retry: 0))
        XCTAssertNotEqual(initial, .init(scenarioID: "study-a", retry: 1))
        XCTAssertEqual(initial, .init(scenarioID: "study-a", retry: 0))
    }

    private func makeRecording(missedTouches: Int = 0) -> ReplayNativeBallPhysics.Recording {
        let samples = [0.0, 1.0].map { time in
            ReplayNativeBallPhysics.Sample(time: time, position: [Float(time), 0.11, 0],
                orientation: simd_quatf(real: 1, imag: .zero), velocity: [1, 0, 0], angularVelocity: .zero)
        }
        return .init(samples: samples, touches: [], missedTouchCount: missedTouches)
    }
}
