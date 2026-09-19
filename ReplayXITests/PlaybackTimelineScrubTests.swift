import XCTest
@testable import ReplayXI

final class PlaybackTimelineScrubTests: XCTestCase {
    func testScrubGenerationChangesOnlyForNewAcceptedTransactionsAndStaysLocal() throws {
        let store = ReplayStore()
        XCTAssertNil(store.activeTimelineScrubID)
        store.beginDrawing(.arc)
        XCTAssertFalse(store.beginTimelineScrub())
        XCTAssertNil(store.activeTimelineScrubID)
        store.cancelDrawing()
        XCTAssertTrue(store.beginTimelineScrub())
        let first = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertEqual(store.activeTimelineScrubID, first, "Idempotent begin must not replace the current owner")
        XCTAssertTrue(store.previewTimelineScrub(to: 4))
        XCTAssertEqual(store.activeTimelineScrubID, first)
        let encoded = String(decoding: try JSONEncoder().encode(store.makeSavedReviewState()), as: UTF8.self)
        XCTAssertFalse(encoded.contains(first.uuidString))
        XCTAssertFalse(encoded.contains("activeTimelineScrubID"))
        XCTAssertTrue(store.commitTimelineScrub(to: 4))
        XCTAssertNil(store.activeTimelineScrubID)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.beginTimelineScrub())
        let second = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertNotEqual(second, first)
        XCTAssertFalse(store.commitTimelineScrub(to: .nan))
        XCTAssertNil(store.activeTimelineScrubID)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertNotEqual(store.activeTimelineScrubID, second)
        store.prepareForImmersiveExit()
        XCTAssertNil(store.activeTimelineScrubID)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        store.cancelTimelineScrub()
        XCTAssertNil(store.activeTimelineScrubID)
    }

    func testStoreOwnsScrubMasksPreviewAndBlocksCompetingSpatialMutation() throws {
        let store = ReplayStore()
        store.playhead = 5
        store.isPlaying = true
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(PitchPoint(x: 2, z: 3))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 6, z: 8)))
        store.cancelDrawing()
        store.isPlaying = true

        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.previewTimelineScrub(to: 12.5))
        XCTAssertEqual(store.playhead, 12.5)

        let masked = store.makeSnapshot()
        XCTAssertEqual(masked.playhead, 5)
        XCTAssertTrue(masked.isPlaying)
        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: 9, z: 9),
                end: PitchPoint(x: 12, z: 12),
                broadcast: false
            )
        )
        XCTAssertNil(
            store.previewCoachMarkEndpoint(
                id: mark.id,
                endpoint: .end,
                gestureID: UUID(),
                cumulativeDelta: PitchPoint(x: 0.5, z: 0.5)
            ),
            "A second-hand joystick edit must not enter while scrub owns the transaction."
        )
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(store.marks.first(where: { $0.id == mark.id }), mark)

        XCTAssertTrue(store.commitTimelineScrub(to: 12.5))
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 12.5)
        XCTAssertTrue(store.isPlaying)
    }

    func testInterruptedScrubRestoresLocalPauseAndExitCannotResumePlayback() {
        let store = ReplayStore()
        store.playhead = 7
        store.isPlaying = true
        store.isLocallyPaused = true
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 19))
        store.cancelTimelineScrub()
        XCTAssertEqual(store.playhead, 7)
        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(store.isLocallyPaused)
        XCTAssertFalse(store.isActivelyPlaying)

        store.isLocallyPaused = false
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 21))
        store.prepareForImmersiveExit()
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 7)
        XCTAssertFalse(store.isPlaying)
    }

    func testPinchCanStartAnywhereOnRailAndClamps() {
        XCTAssertEqual(
            PlaybackTimelineScrub.begin(
                atRailLocation: 50,
                duration: 120,
                railWidth: 200
            ).time,
            30,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.begin(
                atRailLocation: 400,
                duration: 120,
                railWidth: 200
            ).time,
            120,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.begin(
                atRailLocation: -.infinity,
                duration: 120,
                railWidth: 200
            ).time,
            0,
            accuracy: 0.000_001
        )
    }

    func testHorizontalTravelUsesCoarseFineAndFrameGain() {
        var state = PlaybackTimelineScrub.begin(at: 20, duration: 100)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 40,
            verticalTranslation: 0
        )
        XCTAssertEqual(state.time, 40, accuracy: 0.000_001)
        XCTAssertEqual(state.precision, .coarse)

        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 40,
            verticalTranslation: 60
        )
        XCTAssertEqual(state.time, 40, accuracy: 0.000_001)
        XCTAssertEqual(state.precision, .fine)

        let fineGain = PlaybackTimelineScrub.gain(forVerticalTravel: 60)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 80,
            verticalTranslation: 60
        )
        XCTAssertEqual(state.precision, .fine)
        XCTAssertEqual(state.time, 40 + 20 * fineGain, accuracy: 0.000_001)
    }

    func testVerticalPrecisionChangesPreserveReachedTime() {
        var state = PlaybackTimelineScrub.begin(at: 20, duration: 100)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 40,
            verticalTranslation: 0
        )
        let reachedTime = state.time

        for verticalTravel: CGFloat in [41, 42, 60, 95, 96, 120] {
            state = PlaybackTimelineScrub.update(
                state,
                duration: 100,
                railWidth: 200,
                horizontalTranslation: 40,
                verticalTranslation: verticalTravel
            )
            XCTAssertEqual(state.time, reachedTime, accuracy: 0.000_001)
        }

        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 41), .coarse)
        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 42), .fine)
        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 95), .fine)
        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 96), .frame)
    }

    func testFramePrecisionSnapsOnlyAfterHorizontalTravel() {
        var state = PlaybackTimelineScrub.begin(at: 10.017, duration: 100)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 300,
            horizontalTranslation: 0,
            verticalTranslation: 110
        )
        XCTAssertEqual(
            state.time,
            10.017,
            accuracy: 0.000_001,
            "Lifting into frame mode must not move the playhead"
        )

        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 300,
            horizontalTranslation: 7,
            verticalTranslation: 110
        )
        XCTAssertEqual(state.precision, .frame)
        XCTAssertEqual(
            state.time * PlaybackTimelineScrub.frameRate,
            (state.time * PlaybackTimelineScrub.frameRate).rounded(),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.snappedToFrame(99.999, duration: 100),
            100,
            accuracy: 0.000_001
        )
    }

    func testGestureSamplesClampAndRejectInvalidGeometry() {
        let nearEnd = PlaybackTimelineScrub.begin(at: 99, duration: 100)
        XCTAssertEqual(
            PlaybackTimelineScrub.update(
                nearEnd,
                duration: 100,
                railWidth: 200,
                horizontalTranslation: 500,
                verticalTranslation: 0
            ).time,
            100
        )
        let nearStart = PlaybackTimelineScrub.begin(at: 1, duration: 100)
        XCTAssertEqual(
            PlaybackTimelineScrub.update(
                nearStart,
                duration: 100,
                railWidth: 200,
                horizontalTranslation: -500,
                verticalTranslation: 0
            ).time,
            0
        )
        let valid = PlaybackTimelineScrub.begin(at: 12, duration: 100)
        XCTAssertEqual(
            PlaybackTimelineScrub.update(
                valid,
                duration: 100,
                railWidth: 0,
                horizontalTranslation: 80,
                verticalTranslation: 0
            ).time,
            12
        )
    }

    func testAccessibilityAdjustmentUsesOneSecondAndClamps() {
        XCTAssertEqual(
            PlaybackTimelineScrub.adjustedTime(4, direction: 1, duration: 10),
            5
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.adjustedTime(0.2, direction: -1, duration: 10),
            0
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.adjustedTime(9.8, direction: 1, duration: 10),
            10
        )
    }

    func testDashboardSliderUsesStoreOwnedScrubTransaction() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("ReplayXI")
            .appendingPathComponent("UI")
            .appendingPathComponent("ReplayDashboardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(
            source.range(of: "private struct DashboardTransport: View")?.lowerBound
        )
        let end = try XCTUnwrap(
            source.range(
                of: "private struct PlaybackConsole: View",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let transport = String(source[start..<end])

        XCTAssertTrue(transport.contains("store.beginTimelineScrub()"))
        XCTAssertTrue(transport.contains("store.previewTimelineScrub(to: time)"))
        XCTAssertTrue(transport.contains("store.commitTimelineScrub(to: finalPlayhead)"))
        XCTAssertTrue(transport.contains("store.cancelTimelineScrub()"))
        XCTAssertFalse(transport.contains("wasPlayingBeforeScrub"))
    }
}
