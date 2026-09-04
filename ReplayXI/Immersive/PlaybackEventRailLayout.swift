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
        /// Retained for source compatibility with the first bounded
        /// implementation. Events are now bounded by the number of output
        /// bins rather than by dropping input, so this is always zero.
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
    /// The input collection is never copied or sorted. Every finite event is
    /// aggregated into at most 128 direct-indexed bins, then output compaction
    /// happens in-place. This keeps the chronological tail and a late selected
    /// event visible without allowing render storage to grow with the import.
    /// Collection order does not affect cluster positions or counts.
    @discardableResult
    static func clusterTimelineTicks<Events: Collection>(
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

        var acceptedEventCount = 0
        var ignoredNonFiniteEventCount = 0

        for event in events {
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
            truncatedEventCount: 0,
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

/// An allocation-free digest of the metadata that can change the ordered
/// review shelf or timeline rail. Spatial endpoint edits are intentionally
/// absent: a live 3D handle drag must not rebuild and resort timeline data.
struct PlaybackReviewIndexFingerprint: Equatable, Sendable {
    let markCount: Int
    private let firstLane: UInt64
    private let secondLane: UInt64

    init<Marks: Collection>(marks: Marks) where Marks.Element == CoachMark {
        var accumulator = Accumulator()
        var ordinal: UInt64 = 0

        for mark in marks {
            accumulator.mix(ordinal)
            accumulator.mix(mark.id)
            accumulator.mix(Self.code(for: mark.kind))
            accumulator.mix(mark.label)
            accumulator.mix(Self.canonicalBitPattern(of: mark.revealTime))
            if let hideTime = mark.hideTime {
                accumulator.mix(1)
                accumulator.mix(Self.canonicalBitPattern(of: hideTime))
            } else {
                accumulator.mix(0)
            }
            ordinal &+= 1
        }

        markCount = marks.count
        accumulator.mix(UInt64(truncatingIfNeeded: markCount))
        firstLane = accumulator.firstLane
        secondLane = accumulator.secondLane
    }

    private static func canonicalBitPattern(of value: TimeInterval) -> UInt64 {
        // Double considers -0 and +0 equal. Canonicalising zero keeps this
        // fingerprint aligned with the previous Equatable metadata key.
        value == 0 ? 0 : value.bitPattern
    }

    private static func code(for kind: CoachMarkKind) -> UInt64 {
        switch kind {
        case .run: 0
        case .pass: 1
        case .danger: 2
        case .space: 3
        case .playerLabel: 4
        }
    }

    private struct Accumulator {
        // Two independently mixed 64-bit lanes make an accidental stale-cache
        // collision vanishingly unlikely while keeping comparison constant
        // time. Neither lane allocates or materialises UUID/String arrays.
        fileprivate var firstLane: UInt64 = 0xcbf29ce484222325
        fileprivate var secondLane: UInt64 = 0x6eed0e9da4d94a4f

        mutating func mix(_ value: UInt64) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { bytes in
                for byte in bytes {
                    mix(byte)
                }
            }
        }

        mutating func mix(_ value: UUID) {
            var bytes = value.uuid
            withUnsafeBytes(of: &bytes) { buffer in
                for byte in buffer {
                    mix(byte)
                }
            }
        }

        mutating func mix(_ value: String) {
            mix(UInt64(value.utf8.count))
            for byte in value.utf8 {
                mix(byte)
            }
        }

        private mutating func mix(_ byte: UInt8) {
            firstLane ^= UInt64(byte)
            firstLane &*= 0x100000001b3

            secondLane ^= UInt64(byte) &+ 0x9e
            secondLane = (secondLane << 13) | (secondLane >> 51)
            secondLane &*= 0x9e3779b185ebca87
        }
    }
}

/// Scalar token observed by the control deck instead of rebuilding an array of
/// metadata keys on every playhead render.
struct PlaybackReviewIndexVersion: Equatable, Hashable, Sendable {
    fileprivate(set) var rawValue: UInt64 = 0
}

/// Store-owned cache for review-index invalidation. `refresh` is intended for
/// discrete annotation metadata mutations and sanitized remote snapshots, not
/// the render loop. Its work is allocation-free and bounded by the store's
/// supported mark count; unchanged metadata leaves `version` untouched.
struct PlaybackReviewIndexVersionCache: Sendable {
    private var fingerprint: PlaybackReviewIndexFingerprint?
    private(set) var version = PlaybackReviewIndexVersion()

    init() {}

    init<Marks: Collection>(marks: Marks) where Marks.Element == CoachMark {
        fingerprint = PlaybackReviewIndexFingerprint(marks: marks)
    }

    /// Seeds a scenario already handled by a separate scenario-ID observer,
    /// avoiding a redundant second index rebuild.
    mutating func seed<Marks: Collection>(marks: Marks) where Marks.Element == CoachMark {
        fingerprint = PlaybackReviewIndexFingerprint(marks: marks)
    }

    @discardableResult
    mutating func refresh<Marks: Collection>(
        marks: Marks
    ) -> Bool where Marks.Element == CoachMark {
        let nextFingerprint = PlaybackReviewIndexFingerprint(marks: marks)
        guard nextFingerprint != fingerprint else { return false }
        fingerprint = nextFingerprint
        version.rawValue &+= 1
        return true
    }
}
