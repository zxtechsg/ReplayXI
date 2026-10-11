import AVFoundation
import CoreVideo
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayConversionPreviewTests: XCTestCase {
    func testCaptureFreezesTheStudyAndMarksWithoutChangingStore() throws {
        let store = ReplayStore(scenarios: FootballReferenceScenarios.all)
        let first = store.selectedScenario
        let session = ReplayConversionPreviewSession()
        session.capture(scenario: first, marks: store.marks, playhead: 2,
                        perspectiveID: first.defaultPerspectiveID)
        let capturedID = try XCTUnwrap(session.capture).id
        let capturedMarks = session.capture?.marks
        store.selectScenario(id: FootballReferenceScenarios.all[1].id, broadcast: false)
        XCTAssertEqual(session.capture?.scenario.id, first.id)
        XCTAssertEqual(session.capture?.id, capturedID)
        XCTAssertEqual(session.capture?.marks, capturedMarks)
        XCTAssertEqual(session.playhead, 2)
        XCTAssertNotEqual(store.selectedScenarioID, first.id)
        XCTAssertEqual(store.playhead, 0)
    }

    func testCaptureValidatesTimeAndPerspectiveAndResetsOnlyPreview() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let session = ReplayConversionPreviewSession()
        session.capture(scenario: scenario, marks: [], playhead: .infinity, perspectiveID: "invalid")
        XCTAssertEqual(session.playhead, 0)
        XCTAssertEqual(session.capture?.perspectiveID, scenario.defaultPerspectiveID)
        XCTAssertEqual(session.capture?.reference, ReplayReferenceLibrary.reference(for: scenario.id))
        session.isPlaying = true
        session.playbackRate = 4
        let previousID = session.capture?.id
        session.capture(scenario: scenario, marks: [], playhead: scenario.duration + 20,
                        perspectiveID: scenario.defaultPerspectiveID)
        XCTAssertEqual(session.playhead, scenario.duration)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.playbackRate, 1)
        XCTAssertNotEqual(session.capture?.id, previousID)
    }

    func testRoomClockPolicyKeepsStoreTimeThroughClosingAndBlocksTransitionCalibration() {
        let id = "study-a"
        XCTAssertFalse(ReplayReferenceRoomClockPolicy.matches(
            isPresenting: false, scenarioID: id, captureScenarioID: id))
        XCTAssertTrue(ReplayReferenceRoomClockPolicy.matches(
            isPresenting: true, scenarioID: id, captureScenarioID: id))
        XCTAssertFalse(ReplayReferenceRoomClockPolicy.matches(
            isPresenting: true, scenarioID: "study-b", captureScenarioID: id))
        XCTAssertTrue(ReplayReferenceRoomClockPolicy.canCalibrate(
            isPresenting: false, isTransitioning: false, matchesCapture: false))
        XCTAssertTrue(ReplayReferenceRoomClockPolicy.canCalibrate(
            isPresenting: true, isTransitioning: false, matchesCapture: true))
        XCTAssertFalse(ReplayReferenceRoomClockPolicy.canCalibrate(
            isPresenting: true, isTransitioning: true, matchesCapture: true),
            "A matching room still cannot calibrate while opening or closing")
        XCTAssertFalse(ReplayReferenceRoomClockPolicy.canCalibrate(
            isPresenting: true, isTransitioning: false, matchesCapture: false))
    }

    func testExternallyOpenedMatchingRoomHandsFinalTimeBackOnce() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let session = ReplayConversionPreviewSession()
        session.capture(scenario: scenario, marks: [], playhead: 2,
            perspectiveID: scenario.defaultPerspectiveID)
        session.isPlaying = true
        // This does not call the comparison window's Enter action.
        session.reconcileRoomClock(isPresenting: true, scenarioID: scenario.id, roomPlayhead: 3)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.playhead, 2)
        session.reconcileRoomClock(isPresenting: true, scenarioID: scenario.id, roomPlayhead: 8)
        XCTAssertEqual(session.playhead, 2, "Closing is still a room presentation")
        session.reconcileRoomClock(isPresenting: false, scenarioID: scenario.id, roomPlayhead: 9)
        XCTAssertEqual(session.playhead, 9)
        session.seek(to: 4)
        session.reconcileRoomClock(isPresenting: false, scenarioID: scenario.id, roomPlayhead: 10)
        XCTAssertEqual(session.playhead, 4, "A later preview seek must stay independent")
    }

    func testMismatchedRoomCannotHandItsTimeToCapturedStudy() throws {
        let scenarios = FootballReferenceScenarios.all
        let first = try XCTUnwrap(scenarios.first)
        let other = try XCTUnwrap(scenarios.first { $0.id != first.id })
        let session = ReplayConversionPreviewSession()
        session.capture(scenario: first, marks: [], playhead: 2,
            perspectiveID: first.defaultPerspectiveID)
        session.reconcileRoomClock(isPresenting: true, scenarioID: other.id, roomPlayhead: 8)
        session.reconcileRoomClock(isPresenting: false, scenarioID: other.id, roomPlayhead: 9)
        XCTAssertEqual(session.playhead, 2)
        session.reconcileRoomClock(isPresenting: true, scenarioID: first.id, roomPlayhead: 5)
        session.reconcileRoomClock(isPresenting: true, scenarioID: other.id, roomPlayhead: 10)
        session.reconcileRoomClock(isPresenting: false, scenarioID: other.id, roomPlayhead: 11)
        XCTAssertEqual(session.playhead, 2, "A later study switch must not copy its final clock")
    }

    func testPreviewClockIsBoundedSeekableAndStopsAtEnd() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let session = ReplayConversionPreviewSession()
        session.capture(scenario: scenario, marks: [], playhead: 0,
                        perspectiveID: scenario.defaultPerspectiveID)
        session.advance(by: 1)
        XCTAssertEqual(session.playhead, 0)
        session.togglePlayback()
        session.advance(by: .nan)
        session.advance(by: -1)
        XCTAssertEqual(session.playhead, 0)
        session.advance(by: 30)
        XCTAssertEqual(session.playhead, 0.1, accuracy: 0.0001)
        session.seek(to: scenario.duration - 0.01)
        session.advance(by: 0.05)
        XCTAssertEqual(session.playhead, scenario.duration)
        XCTAssertFalse(session.isPlaying)
        session.togglePlayback()
        XCTAssertEqual(session.playhead, 0)
        XCTAssertTrue(session.isPlaying)
        session.seek(to: -2)
        XCTAssertEqual(session.playhead, 0)
    }

    func testSyntheticDemoDoesNotAcquireAnOfficialReference() throws {
        let scenario = try XCTUnwrap(DemoScenarios.all.first)
        let session = ReplayConversionPreviewSession()
        session.capture(scenario: scenario, marks: [], playhead: 0,
                        perspectiveID: scenario.defaultPerspectiveID)
        XCTAssertNil(session.capture?.reference)
    }

    func testEmbedValidationCannotInjectScriptOrImpersonateAnotherClient() {
        XCTAssertTrue(ReplayReferenceEmbed.accepts(videoID: "RgqKdplLIk4"))
        XCTAssertTrue(ReplayReferenceEmbed.accepts(videoID: "05ny1bmo-Kk"))
        XCTAssertFalse(ReplayReferenceEmbed.accepts(videoID: "';alert(1)//"))
        XCTAssertFalse(ReplayReferenceEmbed.accepts(videoID: "https://youtube.com"))
        XCTAssertEqual(ReplayReferenceEmbed.clientOrigin(bundleID: "ReplayXI.zx.zx.NUS")?.absoluteString,
                       "https://replayxi.zx.zx.nus")
        XCTAssertNil(ReplayReferenceEmbed.clientOrigin(bundleID: "evil.test/path'"))
        XCTAssertNil(ReplayReferenceEmbed.clientOrigin(bundleID: ""))
        XCTAssertTrue(ReplayReferenceEmbed.errorMessage(code: 101).contains("publisher"))
        XCTAssertTrue(ReplayReferenceEmbed.errorMessage(code: 153).contains("verify"))
    }

    func testLocalTimeAlignmentMatchesBothAnchorsAndScalesBetweenThem() throws {
        let map = try XCTUnwrap(ReplayReferenceTimeAlignment(
            start: .init(replay: 2, video: 25), end: .init(replay: 10, video: 37), videoDuration: 60))
        XCTAssertEqual(map.rate, 1.5)
        XCTAssertEqual(map.videoTime(for: 2), 25)
        XCTAssertEqual(map.videoTime(for: 10), 37)
        XCTAssertEqual(map.videoTime(for: 6), 31)
        XCTAssertEqual(map.videoTime(for: 0), 22, "An offset may extend before the first matched moment")
        XCTAssertNil(map.videoTime(for: 30), "Do not invent frames beyond the clip")
        XCTAssertNil(map.videoTime(for: .nan))
    }

    func testLocalTimeAlignmentRejectsReversedTinyAndExtremeSpans() {
        func map(_ r0: Double, _ v0: Double, _ r1: Double, _ v1: Double, _ duration: Double = 60)
            -> ReplayReferenceTimeAlignment? {
            .init(start: .init(replay: r0, video: v0), end: .init(replay: r1, video: v1), videoDuration: duration)
        }
        XCTAssertNil(map(2, 10, 1, 11))
        XCTAssertNil(map(1, 10, 2, 9))
        XCTAssertNil(map(0, 0, 0.05, 0.1))
        XCTAssertNil(map(0, 0, 1, 5))
        XCTAssertNil(map(0, 0, 1, 0.2))
        XCTAssertNil(map(-1, 0, 2, 2))
        XCTAssertNil(map(0, -1, 2, 2))
        XCTAssertNil(map(0, 0, 2, 61))
        XCTAssertNil(map(0, 0, 2, 2, .infinity))
        XCTAssertNil(map(.nan, 0, 2, 2))
        XCTAssertNotNil(map(0, 0, 1, 0.25))
        XCTAssertNotNil(map(0, 0, 1, 4))
    }

    func testPreviewLayoutFitsBothAxesAndRejectsNonFiniteSizes() {
        let landscape = ReplayComparisonPitchLayout(width: 0.65, height: 0.4)
        XCTAssertLessThanOrEqual(landscape.scale * 120, 0.65)
        XCTAssertLessThanOrEqual(landscape.scale * 88, 0.4)
        XCTAssertGreaterThan(landscape.depthOffset, 0)
        let invalid = ReplayComparisonPitchLayout(width: .nan, height: -.infinity)
        XCTAssertTrue(invalid.scale.isFinite)
        XCTAssertGreaterThan(invalid.scale, 0)
    }

    func testPlayFramingIsFixedIncludesWholeBallPathAndEnlargesShortPlays() throws {
        for scenario in FootballReferenceScenarios.all {
            let focus = ReplayComparisonPitchFocus(scenario: scenario)
            for frame in scenario.ball.keyframes {
                XCTAssertLessThanOrEqual(abs(frame.position.x - focus.centre.x), focus.width / 2,
                                         scenario.id)
                XCTAssertLessThanOrEqual(abs(frame.position.z - focus.centre.z), focus.length / 2,
                                         scenario.id)
            }
            XCTAssertEqual(focus, ReplayComparisonPitchFocus(scenario: scenario))
        }
        let city = try XCTUnwrap(CityLiverpoolReferenceScenarios.all.first)
        let whole = ReplayComparisonPitchLayout(width: 0.65, height: 0.4)
        let close = ReplayComparisonPitchLayout(width: 0.65, height: 0.4,
            focus: ReplayComparisonPitchFocus(scenario: city))
        XCTAssertGreaterThan(close.scale, whole.scale * 1.5)
        XCTAssertLessThan(close.tilt, whole.tilt)
        let counter = ReplayComparisonPitchFocus(scenario: WorldCupCounterReference.scenario)
        XCTAssertGreaterThan(counter.length, 70, "Do not crop away the counterattack build-up")
    }

    func testLocalImportRejectsNetworkURLAndClearsWithoutReviewPersistence() async {
        let local = ReplayLocalReferencePlayer()
        await local.open(URL(string: "https://example.com/clip.mp4")!)
        XCTAssertNil(local.player)
        XCTAssertNotNil(local.error)
        local.clear()
        XCTAssertNil(local.error)
        XCTAssertNil(local.player)
    }

    func testLocalClipOpensAsPlayableMediaAndClearReleasesTheItem() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replayxi-comparison-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeTinyVideo(to: url)

        let local = ReplayLocalReferencePlayer()
        await local.open(url)
        XCTAssertNil(local.error)
        XCTAssertEqual(local.filename, url.lastPathComponent)
        let player = try XCTUnwrap(local.player)
        let item = try XCTUnwrap(player.currentItem)
        let playable = try await item.asset.load(.isPlayable)
        let duration = try await item.asset.load(.duration).seconds
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration, 0)
        XCTAssertEqual(local.duration, duration)
        local.setAlignmentStart(replayTime: 0)
        XCTAssertNotNil(local.alignmentStart)
        local.setAlignmentEnd(replayTime: 0)
        XCTAssertNotNil(local.alignmentMessage, "The same instant cannot establish a time scale")
        XCTAssertNil(local.alignment)
        local.isTimelineLinked = true
        local.resetAlignment()
        XCTAssertNil(local.alignmentStart)
        XCTAssertNil(local.alignmentMessage)
        XCTAssertFalse(local.isTimelineLinked)
        local.clear()
        XCTAssertNil(local.player)
        XCTAssertNil(player.currentItem, "Clear must detach the item, not just hide its UI")
        XCTAssertNil(local.error)
        XCTAssertEqual(local.duration, 0)
    }

    func testCancelledLocalOpenDoesNotAcquireAPlayerOrReplaceCurrentState() async {
        let local = ReplayLocalReferencePlayer()
        let task = Task { @MainActor in
            await local.open(URL(fileURLWithPath: "/not-opened-cancelled-reference.mp4"))
        }
        // Both tasks are on MainActor; cancellation is set before the child can
        // run, making this deterministic without artificial delays or file I/O.
        task.cancel()
        await task.value
        XCTAssertNil(local.player)
        XCTAssertNil(local.error)
        XCTAssertEqual(local.filename, "Local clip")
    }

    func testLinkedLocalTimelineSeeksLatestTimeAndClearDropsCalibration() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replayxi-alignment-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeTinyVideo(to: url, frameCount: 60)
        let local = ReplayLocalReferencePlayer()
        await local.open(url)
        let player = try XCTUnwrap(local.player)
        local.setAlignmentStart(replayTime: 0)
        await player.seek(to: CMTime(seconds: 1, preferredTimescale: 600),
                          toleranceBefore: .zero, toleranceAfter: .zero)
        local.setAlignmentEnd(replayTime: 1)
        XCTAssertNotNil(local.alignment)
        local.isTimelineLinked = true
        for time in [0.2, 0.7, 0.3, 0.8] {
            local.synchronize(replayTime: time, playing: false, replayRate: 1)
        }
        for _ in 0..<200 where abs(player.currentTime().seconds - 0.8) > 0.03 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(player.currentTime().seconds, 0.8, accuracy: 0.03)
        XCTAssertEqual(player.rate, 0)
        local.suspendLink(message: "Return to this study to link its video.")
        XCTAssertEqual(local.alignmentMessage, "Return to this study to link its video.")
        XCTAssertNotNil(local.alignment, "Changing rooms must not discard the matched clip")
        local.synchronize(replayTime: 0.8, playing: false, replayRate: 1)
        XCTAssertNil(local.alignmentMessage)
        local.synchronize(replayTime: 10, playing: true, replayRate: 1)
        XCTAssertEqual(local.alignmentMessage, "Outside this clip")
        XCTAssertEqual(player.rate, 0)
        local.synchronize(replayTime: 0.4, playing: false, replayRate: 1)
        XCTAssertTrue(local.isSeeking)
        let originalStart = local.alignmentStart
        local.isTimelineLinked = false
        local.setAlignmentStart(replayTime: 0.4)
        XCTAssertEqual(local.alignmentStart, originalStart,
                       "A match point must not capture a frame while a seek is unfinished")
        XCTAssertEqual(local.alignmentMessage, "Wait for the clip to finish seeking.")
        for _ in 0..<200 where local.isSeeking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(local.isSeeking)
        local.setAlignmentStart(replayTime: 0.4)
        XCTAssertNil(local.alignmentMessage)
        XCTAssertEqual(local.alignmentStart?.replay, 0.4)
        local.clear()
        XCTAssertNil(local.alignment)
        XCTAssertNil(local.alignmentStart)
        XCTAssertFalse(local.isTimelineLinked)
        XCTAssertNil(player.currentItem)
    }

    private func writeTinyVideo(to url: URL, frameCount: Int = 3) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ])
        guard writer.canAdd(input) else { throw FixtureError.writerUnavailable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.writerUnavailable }
        writer.startSession(atSourceTime: .zero)
        do {
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            for frame in 0..<frameCount {
                for _ in 0..<200 where !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard input.isReadyForMoreMediaData else { throw FixtureError.writerUnavailable }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else { throw FixtureError.pixelBufferUnavailable }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer) {
                    memset(base, Int32((40 + frame * 40) % 256),
                           CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
                else { throw writer.error ?? FixtureError.writerUnavailable }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? FixtureError.writerUnavailable }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private enum FixtureError: Error { case writerUnavailable, pixelBufferUnavailable }
}
