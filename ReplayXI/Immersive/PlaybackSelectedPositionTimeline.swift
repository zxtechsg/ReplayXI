import SwiftUI

/// Only the selected mark's timestamps invalidate its rail. Geometry, labels,
/// visibility windows and ordinary playhead updates do not rebuild these bins.
struct PlaybackSelectedPositionTimelineSnapshot: Equatable {
    let annotationID: UUID?
    let duration: TimeInterval
    let times: [TimeInterval]

    init(mark: CoachMark?, duration: TimeInterval) {
        self.annotationID = mark?.id
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        let replayDuration = self.duration
        self.times = (mark?.keyframes ?? []).prefix(CoachMark.maximumKeyframes).compactMap {
            $0.time.isFinite && (0...replayDuration).contains($0.time) ? $0.time : nil
        }
    }
}

struct PlaybackSelectedPositionTimelineCache {
    private(set) var clusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
    private(set) var keyCount: Int?
    private var snapshot: PlaybackSelectedPositionTimelineSnapshot?
    private var railWidth: CGFloat = -1
    private var leadingInset: CGFloat = -1

    @discardableResult
    mutating func update(_ next: PlaybackSelectedPositionTimelineSnapshot,
                         railWidth: CGFloat, leadingInset: CGFloat) -> Bool {
        let width = railWidth.isFinite ? max(railWidth, 0) : 0
        let inset = leadingInset.isFinite ? leadingInset : 0
        guard snapshot != next || self.railWidth != width || self.leadingInset != inset else { return false }
        snapshot = next
        self.railWidth = width
        self.leadingInset = inset
        keyCount = next.annotationID.map { _ in next.times.count }
        PlaybackEventRailLayout.clusterTimelineTicks(next.times, duration: next.duration,
            railWidth: width, leadingInset: inset, minimumPixelSpacing: 14,
            into: &clusters, time: { $0 }, kind: { _ in .annotation })
        return true
    }

    static func accessibilitySummary(keyCount: Int?) -> String {
        guard let keyCount else { return "" }
        return "; selected annotation, \(keyCount) saved \(keyCount == 1 ? "position" : "positions")"
    }
}

/// This child observes annotation edits, not playback time. Keeping that read
/// out of the transport's per-frame body avoids mapping every key during replay.
struct PlaybackSelectedPositionTimeline: View {
    @Environment(ReplayStore.self) private var store
    let annotationID: UUID?
    let railWidth: CGFloat
    let leadingInset: CGFloat
    @Binding var keyCount: Int?
    @State private var cache = PlaybackSelectedPositionTimelineCache()

    private struct Input: Equatable {
        let snapshot: PlaybackSelectedPositionTimelineSnapshot
        let width: CGFloat
        let inset: CGFloat
    }

    private var input: Input {
        let mark = annotationID.flatMap { id in store.marks.first { $0.id == id } }
        return Input(snapshot: .init(mark: mark, duration: store.selectedScenario.duration),
                     width: railWidth.isFinite ? max(railWidth, 0) : 0,
                     inset: leadingInset.isFinite ? leadingInset : 0)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(cache.clusters, id: \.binIndex) { cluster in
                Image(systemName: cluster.eventCount > 1 ? "diamond.inset.filled" : "diamond.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ReplayTheme.cyan)
                    .shadow(color: ReplayTheme.navy, radius: 1)
                    .position(x: cluster.x, y: 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: input, initial: true) { _, input in
            guard cache.update(input.snapshot, railWidth: input.width, leadingInset: input.inset) else { return }
            if keyCount != cache.keyCount { keyCount = cache.keyCount }
        }
    }
}
