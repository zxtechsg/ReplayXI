import Foundation
import SwiftUI

/// The event shelf has a deliberately bounded layout. Spatial controls should
/// never communicate overflow by showing a clipped, untappable fragment of the
/// next event, and the coach's primary draw action must never surrender its
/// label to compression.
enum PlaybackEventRailLayout {
    static let itemsPerPage = 3
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
        guard !eventTimes.isEmpty else { return 0 }
        let time = rawTime.isFinite ? rawTime : 0
        var nearestIndex = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        for (index, candidate) in eventTimes.enumerated() where candidate.isFinite {
            let distance = abs(candidate - time)
            if distance < nearestDistance {
                nearestIndex = index
                nearestDistance = distance
            }
        }
        return page(containing: nearestIndex, eventCount: eventTimes.count)
    }

    static func rangeLabel(eventCount: Int, page: Int) -> String {
        let range = visibleRange(eventCount: eventCount, page: page)
        guard !range.isEmpty else { return "NO EVENTS" }
        return "\(range.lowerBound + 1)–\(range.upperBound) OF \(eventCount)"
    }
}
