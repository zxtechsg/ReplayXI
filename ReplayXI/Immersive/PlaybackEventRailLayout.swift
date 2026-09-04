import Foundation
import SwiftUI

/// The event shelf has a deliberately bounded layout. Spatial controls should
/// never communicate overflow by showing a clipped, untappable fragment of the
/// next event, and the coach's primary draw action must never surrender its
/// label to compression.
enum PlaybackEventRailLayout {
    static let itemsPerPage = 3
    /// Timeline density is deliberately finite. A match import can contain
    /// far more telemetry than a coach can distinguish on a hand-scale rail,
    /// so the visual index does a bounded amount of work while the complete
    /// event shelf remains available for detailed navigation.
    static let maximumTimelineTickCount = 128
    /// Selected ticks render eight points wide; a nine-point pitch preserves a
    /// visible gap even when two adjacent bins are both emphasized.
    static let defaultMinimumTimelineTickSpacing: CGFloat = 9
    static let horizontalSpacing: CGFloat = 8
    static let chipSpacing: CGFloat = 8
    static let chipWidth: CGFloat = 190
    static let closeWidth: CGFloat = 56
    static let headingWidth: CGFloat = 82
    static let pageButtonWidth: CGFloat = 54
    static let drawWidth: CGFloat = 116

    /// Width needed by the coach variant at its most dense, including all
    /// fixed controls and the gaps between its six top-level children.
    static let minimumCoachContentWidth: CGFloat =
        closeWidth
        + headingWidth
        + pageButtonWidth * 2
        + drawWidth
        + chipWidth * CGFloat(itemsPerPage)
        + chipSpacing * CGFloat(itemsPerPage - 1)
        + horizontalSpacing * 5

    enum TimelineTickKind: UInt8, Sendable {
        case cue
        case annotation
    }

    /// One renderable timeline position. Several events may intentionally
    /// share a cluster when their projected positions occupy the same pixel
    /// bin. `binIndex` is a stable identity for SwiftUI's `ForEach`.
    struct TimelineTickCluster: Equatable, Sendable {
        let binIndex: Int
        let x: CGFloat
        fileprivate(set) var earliestTime: TimeInterval
        fileprivate(set) var latestTime: TimeInterval
        fileprivate(set) var cueCount: Int
        fileprivate(set) var annotationCount: Int
        fileprivate(set) var selectedEventCount: Int

        var eventCount: Int { cueCount + annotationCount }
        var containsSelection: Bool { selectedEventCount > 0 }

        /// An annotation wins a tie because authored coaching intent should
        /// remain visible when it lands on the same instant as an import cue.
        var dominantKind: TimelineTickKind {
            annotationCount >= cueCount ? .annotation : .cue
        }

        fileprivate init(binIndex: Int, x: CGFloat) {
            self.binIndex = binIndex
            self.x = x
            earliestTime = .greatestFiniteMagnitude
            latestTime = -.greatestFiniteMagnitude
            cueCount = 0
            annotationCount = 0
            selectedEventCount = 0
        }
    }

    struct TimelineTickClusteringSummary: Equatable, Sendable {
        let acceptedEventCount: Int
        let ignoredNonFiniteEventCount: Int
        let truncatedEventCount: Int
        let clusterCount: Int
    }

    /// Warms the reusable storage once. Calling `clusterTimelineTicks` with
    /// this buffer thereafter performs no array allocation, including when a
    /// dense import expands from one event to the full supported 128.
    static func prepareTimelineTickClusters(
        _ clusters: inout [TimelineTickCluster]
    ) {
        clusters.removeAll(keepingCapacity: true)
        clusters.reserveCapacity(maximumTimelineTickCount)
    }

    /// Quantizes timeline events into visually separable pixel bins.
    ///
    /// The input collection is never copied or sorted. Aggregation is direct
    /// indexed and output compaction is in-place, making this suitable for a
    /// cached SwiftUI rail buffer. Collection order does not affect cluster
    /// positions or counts. Only the first 128 inputs are inspected; callers
    /// should supply timeline-ordered events when truncation is possible.
    @discardableResult
    static func clusterTimelineTicks<Events: RandomAccessCollection>(
        _ events: Events,
        duration rawDuration: TimeInterval,
        railWidth rawRailWidth: CGFloat,
        leadingInset rawLeadingInset: CGFloat,
        minimumPixelSpacing rawMinimumPixelSpacing: CGFloat =
            defaultMinimumTimelineTickSpacing,
        into clusters: inout [TimelineTickCluster],
        time: (Events.Element) -> TimeInterval,
        kind: (Events.Element) -> TimelineTickKind,
        isSelected: (Events.Element) -> Bool = { _ in false }
    ) -> TimelineTickClusteringSummary {
        if clusters.capacity < maximumTimelineTickCount {
            clusters.reserveCapacity(maximumTimelineTickCount)
        }
        clusters.removeAll(keepingCapacity: true)

        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 1
        let railWidth = rawRailWidth.isFinite ? max(rawRailWidth, 0) : 0
        let leadingInset = rawLeadingInset.isFinite ? rawLeadingInset : 0
        let minimumPixelSpacing = rawMinimumPixelSpacing.isFinite
                && rawMinimumPixelSpacing > 0
            ? rawMinimumPixelSpacing
            : defaultMinimumTimelineTickSpacing
        let maximumUncappedSpan = minimumPixelSpacing
            * CGFloat(maximumTimelineTickCount - 1)
        let binCount: Int
        if railWidth >= maximumUncappedSpan {
            binCount = maximumTimelineTickCount
        } else {
            binCount = max(
                Int((railWidth / minimumPixelSpacing).rounded(.down)) + 1,
                1
            )
        }
        let lastBinIndex = binCount - 1

        for binIndex in 0..<binCount {
            let progress = lastBinIndex == 0
                ? 0
                : CGFloat(binIndex) / CGFloat(lastBinIndex)
            clusters.append(
                TimelineTickCluster(
                    binIndex: binIndex,
                    x: leadingInset + railWidth * progress
                )
            )
        }

        let inspectedCount = min(events.count, maximumTimelineTickCount)
        var acceptedEventCount = 0
        var ignoredNonFiniteEventCount = 0
        var eventIndex = events.startIndex

        for _ in 0..<inspectedCount {
            let event = events[eventIndex]
            let rawTime = time(event)
            if rawTime.isFinite {
                let clampedTime = min(max(rawTime, 0), duration)
                let progress = clampedTime / duration
                let projectedBin = lastBinIndex == 0
                    ? 0
                    : Int(
                        (progress * Double(lastBinIndex))
                            .rounded(.toNearestOrAwayFromZero)
                    )
                let binIndex = min(max(projectedBin, 0), lastBinIndex)
                var cluster = clusters[binIndex]
                cluster.earliestTime = min(cluster.earliestTime, clampedTime)
                cluster.latestTime = max(cluster.latestTime, clampedTime)
                switch kind(event) {
                case .cue:
                    cluster.cueCount += 1
                case .annotation:
                    cluster.annotationCount += 1
                }
                if isSelected(event) {
                    cluster.selectedEventCount += 1
                }
                clusters[binIndex] = cluster
                acceptedEventCount += 1
            } else {
                ignoredNonFiniteEventCount += 1
            }
            eventIndex = events.index(after: eventIndex)
        }

        // Empty bins are only scratch space. Compact occupied bins in place so
        // the caller can render the result directly without another filter or
        // intermediate array allocation.
        var writeIndex = 0
        for readIndex in 0..<binCount where clusters[readIndex].eventCount > 0 {
            if writeIndex != readIndex {
                clusters[writeIndex] = clusters[readIndex]
            }
            writeIndex += 1
        }
        if writeIndex < clusters.count {
            clusters.removeLast(clusters.count - writeIndex)
        }

        return TimelineTickClusteringSummary(
            acceptedEventCount: acceptedEventCount,
            ignoredNonFiniteEventCount: ignoredNonFiniteEventCount,
            truncatedEventCount: max(events.count - inspectedCount, 0),
            clusterCount: writeIndex
        )
    }

    static func pageCount(eventCount: Int) -> Int {
        max(1, (max(eventCount, 0) + itemsPerPage - 1) / itemsPerPage)
    }

    static func clampedPage(_ page: Int, eventCount: Int) -> Int {
        min(max(page, 0), pageCount(eventCount: eventCount) - 1)
    }

    static func visibleRange(eventCount: Int, page: Int) -> Range<Int> {
        guard eventCount > 0 else { return 0..<0 }
        let resolvedPage = clampedPage(page, eventCount: eventCount)
        let lowerBound = resolvedPage * itemsPerPage
        return lowerBound..<min(lowerBound + itemsPerPage, eventCount)
    }

    static func page(containing index: Int, eventCount: Int) -> Int {
        guard eventCount > 0 else { return 0 }
        let safeIndex = min(max(index, 0), eventCount - 1)
        return clampedPage(safeIndex / itemsPerPage, eventCount: eventCount)
    }

    /// Resolves the event group nearest the current replay instant. The event
    /// array is already timeline ordered, but this intentionally tolerates
    /// malformed/non-finite external metadata and keeps ties on the earlier
    /// event for stable A → B → A navigation.
    static func page(
        nearestTo rawTime: TimeInterval,
        eventTimes: [TimeInterval]
    ) -> Int {
        page(nearestTo: rawTime, events: eventTimes, time: { $0 })
    }

    /// Generic form avoids a temporary `events.map(\.time)` allocation when
    /// opening the shelf from a cached review index.
    static func page<Events: Collection>(
        nearestTo rawTime: TimeInterval,
        events: Events,
        time eventTime: (Events.Element) -> TimeInterval
    ) -> Int {
        guard !events.isEmpty else { return 0 }
        let time = rawTime.isFinite ? rawTime : 0
        var nearestIndex = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        for (index, event) in events.enumerated() {
            let candidate = eventTime(event)
            guard candidate.isFinite else { continue }
            let distance = abs(candidate - time)
            if distance < nearestDistance {
                nearestIndex = index
                nearestDistance = distance
            }
        }
        return page(containing: nearestIndex, eventCount: events.count)
    }

    static func rangeLabel(eventCount: Int, page: Int) -> String {
        let range = visibleRange(eventCount: eventCount, page: page)
        guard !range.isEmpty else { return "NO EVENTS" }
        return "\(range.lowerBound + 1)–\(range.upperBound) OF \(eventCount)"
    }
}
