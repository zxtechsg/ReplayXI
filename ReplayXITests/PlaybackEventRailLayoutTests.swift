import XCTest
@testable import ReplayXI

final class PlaybackEventRailLayoutTests: XCTestCase {
    private struct Tick: Equatable {
        let time: TimeInterval
        let kind: PlaybackEventRailLayout.TimelineTickKind
        let isSelected: Bool
    }

    func testPagingNeverProducesPartialOrMissingEvents() {
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 0), 1)
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 3), 1)
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 4), 2)
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 10), 4)

        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: 0),
            0..<3
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: 1),
            3..<4
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: 99),
            3..<4
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: -99),
            0..<3
        )
    }

    func testCoachRailFitsWithoutCompressingAtConsoleWidth() {
        // 1,200-point deck minus its 44 points of deck padding and the event
        // shelf's 20 points of inset leaves 1,136 points of usable width.
        let availableContentWidth: CGFloat = 1_136
        XCTAssertLessThanOrEqual(
            PlaybackEventRailLayout.minimumCoachContentWidth,
            availableContentWidth
        )
        XCTAssertEqual(PlaybackEventRailLayout.minimumCoachContentWidth, 988)
    }

    func testRangeLabelCommunicatesExactlyWhatPagingWillReveal() {
        XCTAssertEqual(
            PlaybackEventRailLayout.rangeLabel(eventCount: 0, page: 0),
            "NO EVENTS"
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.rangeLabel(eventCount: 7, page: 0),
            "1–3 OF 7"
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.rangeLabel(eventCount: 7, page: 2),
            "7–7 OF 7"
        )
    }

    func testContextualPagingFindsSelectedAndNearestEvents() {
        XCTAssertEqual(
            PlaybackEventRailLayout.page(containing: 0, eventCount: 10),
            0
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(containing: 8, eventCount: 10),
            2
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(containing: 99, eventCount: 10),
            3
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: 20, eventTimes: [2, 8, 19, 21, 29]),
            0,
            "An equal-distance tie stays on the earlier event and its page"
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: 28, eventTimes: [2, 8, 19, 21, 29]),
            1
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: .nan, eventTimes: [2, 8, 19]),
            0
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: 5, eventTimes: []),
            0
        )
        let genericEvents = [
            Tick(time: 2, kind: .cue, isSelected: false),
            Tick(time: 8, kind: .cue, isSelected: false),
            Tick(time: 19, kind: .annotation, isSelected: false),
            Tick(time: 21, kind: .annotation, isSelected: false),
            Tick(time: 29, kind: .cue, isSelected: false),
        ]
        XCTAssertEqual(
            PlaybackEventRailLayout.page(
                nearestTo: 28,
                events: genericEvents,
                time: \Tick.time
            ),
            1
        )
    }

    func testReviewIndexSignatureIgnoresLiveGeometryButTracksRailMetadata() throws {
        let id = try XCTUnwrap(UUID(uuidString: "C63A71EC-F77D-49A4-91B7-10812CB2C33B"))
        let original = CoachMark(
            id: id,
            kind: .run,
            start: PitchPoint(x: 2, z: 3),
            end: PitchPoint(x: 8, z: 12),
            label: "Overlap",
            revealTime: 4,
            hideTime: 9
        )
        let geometryPreview = CoachMark(
            id: id,
            kind: .run,
            start: PitchPoint(x: -20, z: -14),
            end: PitchPoint(x: 18, z: 22),
            label: "Overlap",
            revealTime: 4,
            hideTime: 9
        )

        XCTAssertEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: geometryPreview),
            "A live endpoint preview must not rebuild and sort the event rail"
        )

        let retimed = CoachMark(
            id: id,
            kind: .run,
            start: geometryPreview.start,
            end: geometryPreview.end,
            label: "Overlap",
            revealTime: 6,
            hideTime: 11
        )
        let relabelled = CoachMark(
            id: id,
            kind: .run,
            start: geometryPreview.start,
            end: geometryPreview.end,
            label: "Underlap",
            revealTime: 4,
            hideTime: 9
        )
        let resized = CoachMark(
            id: id,
            kind: .run,
            start: geometryPreview.start,
            end: geometryPreview.end,
            label: "Overlap",
            revealTime: 4,
            hideTime: 12
        )

        XCTAssertNotEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: retimed)
        )
        XCTAssertNotEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: relabelled)
        )
        XCTAssertNotEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: resized)
        )
    }

    func testTimelineTicksClusterIntoStablePixelBins() {
        let events = [
            Tick(time: 1.0, kind: .cue, isSelected: false),
            Tick(time: 1.2, kind: .annotation, isSelected: true),
            Tick(time: 5.0, kind: .cue, isSelected: false),
            Tick(time: 9.7, kind: .annotation, isSelected: false),
        ]
        var clusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
        PlaybackEventRailLayout.prepareTimelineTickClusters(&clusters)

        let summary = PlaybackEventRailLayout.clusterTimelineTicks(
            events,
            duration: 10,
            railWidth: 70,
            leadingInset: 5,
            minimumPixelSpacing: 7,
            into: &clusters,
            time: \Tick.time,
            kind: \Tick.kind,
            isSelected: \Tick.isSelected
        )

        XCTAssertEqual(
            summary,
            .init(
                acceptedEventCount: 4,
                ignoredNonFiniteEventCount: 0,
                truncatedEventCount: 0,
                clusterCount: 3
            )
        )
        XCTAssertEqual(clusters.map(\.binIndex), [1, 5, 10])
        XCTAssertEqual(clusters.map(\.x), [12, 40, 75])

        let denseCluster = clusters[0]
        XCTAssertEqual(denseCluster.earliestTime, 1.0)
        XCTAssertEqual(denseCluster.latestTime, 1.2)
        XCTAssertEqual(denseCluster.cueCount, 1)
        XCTAssertEqual(denseCluster.annotationCount, 1)
        XCTAssertEqual(denseCluster.eventCount, 2)
        XCTAssertEqual(denseCluster.selectedEventCount, 1)
        XCTAssertTrue(denseCluster.containsSelection)
        XCTAssertEqual(denseCluster.dominantKind, .annotation)
    }

    func testTimelineClusteringIsIndependentOfEventOrder() {
        let events = [
            Tick(time: 1.0, kind: .cue, isSelected: false),
            Tick(time: 1.2, kind: .annotation, isSelected: true),
            Tick(time: 5.0, kind: .cue, isSelected: false),
            Tick(time: 9.7, kind: .annotation, isSelected: false),
        ]
        var forward: [PlaybackEventRailLayout.TimelineTickCluster] = []
        var reverse: [PlaybackEventRailLayout.TimelineTickCluster] = []
        PlaybackEventRailLayout.prepareTimelineTickClusters(&forward)
        PlaybackEventRailLayout.prepareTimelineTickClusters(&reverse)

        PlaybackEventRailLayout.clusterTimelineTicks(
            events,
            duration: 10,
            railWidth: 70,
            leadingInset: 5,
            minimumPixelSpacing: 7,
            into: &forward,
            time: \Tick.time,
            kind: \Tick.kind,
            isSelected: \Tick.isSelected
        )
        PlaybackEventRailLayout.clusterTimelineTicks(
            events.reversed(),
            duration: 10,
            railWidth: 70,
            leadingInset: 5,
            minimumPixelSpacing: 7,
            into: &reverse,
            time: \Tick.time,
            kind: \Tick.kind,
            isSelected: \Tick.isSelected
        )

        XCTAssertEqual(forward, reverse)
    }

    func testTimelineClusteringIsBoundedAt128EventsAndClusters() {
        let events = (0..<140).map {
            Tick(time: TimeInterval($0), kind: .annotation, isSelected: false)
        }
        var clusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
        PlaybackEventRailLayout.prepareTimelineTickClusters(&clusters)

        let summary = PlaybackEventRailLayout.clusterTimelineTicks(
            events,
            duration: 127,
            railWidth: 1_000_000,
            leadingInset: 9,
            minimumPixelSpacing: 1,
            into: &clusters,
            time: \Tick.time,
            kind: \Tick.kind
        )

        XCTAssertEqual(summary.acceptedEventCount, 128)
        XCTAssertEqual(summary.truncatedEventCount, 12)
        XCTAssertEqual(summary.clusterCount, 128)
        XCTAssertEqual(clusters.count, PlaybackEventRailLayout.maximumTimelineTickCount)
        XCTAssertEqual(clusters.first?.binIndex, 0)
        XCTAssertEqual(clusters.last?.binIndex, 127)
        XCTAssertEqual(clusters.reduce(0) { $0 + $1.eventCount }, 128)
    }

    func testTimelineClusteringSanitizesInvalidGeometryAndTimes() {
        let events = [
            Tick(time: -.infinity, kind: .cue, isSelected: false),
            Tick(time: .nan, kind: .annotation, isSelected: false),
            Tick(time: -0.5, kind: .cue, isSelected: false),
            Tick(time: 0.5, kind: .annotation, isSelected: true),
            Tick(time: 2, kind: .cue, isSelected: false),
        ]
        var clusters: [PlaybackEventRailLayout.TimelineTickCluster] = []

        let summary = PlaybackEventRailLayout.clusterTimelineTicks(
            events,
            duration: .nan,
            railWidth: .infinity,
            leadingInset: .nan,
            minimumPixelSpacing: 0,
            into: &clusters,
            time: \Tick.time,
            kind: \Tick.kind,
            isSelected: \Tick.isSelected
        )

        XCTAssertEqual(summary.acceptedEventCount, 3)
        XCTAssertEqual(summary.ignoredNonFiniteEventCount, 2)
        XCTAssertEqual(summary.truncatedEventCount, 0)
        XCTAssertEqual(summary.clusterCount, 1)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].x, 0)
        XCTAssertEqual(clusters[0].earliestTime, 0)
        XCTAssertEqual(clusters[0].latestTime, 1)
        XCTAssertEqual(clusters[0].cueCount, 2)
        XCTAssertEqual(clusters[0].annotationCount, 1)
        XCTAssertTrue(clusters[0].containsSelection)
    }

    func testPreparedTimelineBufferRetainsCapacityAcrossDenseRebuilds() {
        let events = (0..<128).map {
            Tick(time: TimeInterval($0), kind: .cue, isSelected: false)
        }
        var clusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
        PlaybackEventRailLayout.prepareTimelineTickClusters(&clusters)
        let preparedCapacity = clusters.capacity

        for width in stride(from: CGFloat(7), through: 889, by: 7) {
            PlaybackEventRailLayout.clusterTimelineTicks(
                events,
                duration: 127,
                railWidth: width,
                leadingInset: 0,
                into: &clusters,
                time: \Tick.time,
                kind: \Tick.kind
            )
            XCTAssertEqual(clusters.capacity, preparedCapacity)
        }
        XCTAssertGreaterThanOrEqual(
            preparedCapacity,
            PlaybackEventRailLayout.maximumTimelineTickCount
        )
    }

    func testAdjacentClusterPositionsRespectMinimumPixelSpacing() {
        let events = (0...100).map {
            Tick(time: TimeInterval($0), kind: .cue, isSelected: false)
        }
        var clusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
        PlaybackEventRailLayout.clusterTimelineTicks(
            events,
            duration: 100,
            railWidth: 101,
            leadingInset: 9,
            minimumPixelSpacing: 8,
            into: &clusters,
            time: \Tick.time,
            kind: \Tick.kind
        )

        XCTAssertEqual(clusters.count, 13)
        for pair in zip(clusters, clusters.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.x - pair.0.x, 8)
        }
        XCTAssertEqual(clusters.first?.x, 9)
        XCTAssertEqual(clusters.last?.x, 110)
    }
}
