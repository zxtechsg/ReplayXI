import SwiftUI

enum SpatialAnnotationTimelineMath {
    enum Handle: Equatable { case start, end, move, key(TimeInterval) }

    static func time(at x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard x.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return 0 }
        return min(max(Double(x / width) * duration, 0), duration)
    }

    static func trim(_ handle: Handle, mark: CoachMark, delta: TimeInterval,
                     duration: TimeInterval) -> (start: TimeInterval, end: TimeInterval?) {
        let end = mark.hideTime ?? duration
        let minimum = CoachMarkTimingPolicy.minimumEditableDuration
        let maximum = CoachMarkTimingPolicy.maximumDuration
        guard delta.isFinite, duration.isFinite, duration > 0 else {
            return (mark.revealTime, mark.hideTime)
        }
        switch handle {
        case .start:
            let lower = mark.hideTime == nil ? 0 : max(0, end - maximum)
            let upper = mark.hideTime == nil ? duration : max(0, end - minimum)
            return (min(max(mark.revealTime + delta, lower),
                        upper), mark.hideTime)
        case .end:
            let proposed = end + delta
            if proposed >= duration - 0.000_001
                || (mark.hideTime == nil && proposed > mark.revealTime + maximum) {
                return (mark.revealTime, nil)
            }
            let value = min(max(proposed, mark.revealTime + minimum),
                            min(duration, mark.revealTime + maximum))
            return (mark.revealTime, value >= duration - 0.000_001 ? nil : value)
        default:
            return (mark.revealTime, mark.hideTime)
        }
    }

    static func movedStart(mark: CoachMark, delta: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard delta.isFinite, duration.isFinite, duration > 0 else { return mark.revealTime }
        let frames = mark.keyframes ?? []
        let earliest = min(mark.revealTime, frames.first?.time ?? mark.revealTime)
        let latest = max(mark.hideTime ?? mark.revealTime, frames.last?.time ?? mark.revealTime)
        return mark.revealTime + min(max(delta, -earliest), max(0, duration - latest))
    }
}

/// Local drag preview; each lift commits one guarded, undoable store edit.
struct SpatialAnnotationTimeline: View {
    @Environment(ReplayStore.self) private var store
    let mark: CoachMark
    var showsTitle = false
    var onSelect: () -> Void = {}
    @State private var drag: Edit?
    @GestureState private var dragging = false

    private struct Edit {
        let scenarioID: String
        let view: ReplayViewMode
        let mark: CoachMark
        let playhead: TimeInterval
        let handle: SpatialAnnotationTimelineMath.Handle
        var delta: TimeInterval = 0
    }

    private var editable: Bool {
        store.localRole == .coach && store.canChangePlaybackView && !store.isDrawing
            && !store.selectedScenario.coachMarks.contains(where: { $0.id == mark.id })
    }

    private var window: (start: TimeInterval, end: TimeInterval?) {
        guard let drag else { return (mark.revealTime, mark.hideTime) }
        if drag.handle == .move {
            let start = SpatialAnnotationTimelineMath.movedStart(mark: mark, delta: drag.delta,
                                                                duration: store.selectedScenario.duration)
            return (start, mark.hideTime.map { $0 + start - mark.revealTime })
        }
        return SpatialAnnotationTimelineMath.trim(drag.handle, mark: mark, delta: drag.delta,
                                                  duration: store.selectedScenario.duration)
    }

    var body: some View {
        HStack(spacing: 10) {
            if showsTitle {
                Button(action: onSelect) {
                    Label(mark.label, systemImage: mark.kind.systemImage)
                        .font(.caption.weight(.semibold)).lineLimit(1)
                        .frame(width: 115, alignment: .leading)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.plain)
                .help("Edit \(mark.label)")
            }
            track
        }
        .onChange(of: store.selectedScenarioID) { _, _ in drag = nil }
        .onChange(of: mark) { _, _ in drag = nil }
        .onChange(of: dragging) { _, active in
            guard !active else { return }
            Task { @MainActor in
                await Task.yield()
                if !dragging { drag = nil }
            }
        }
        .onDisappear { drag = nil }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 88, 1)
            let duration = max(store.selectedScenario.duration, 0.1)
            let startX = 44 + width * CGFloat(window.start / duration)
            let endX = 44 + width * CGFloat((window.end ?? duration) / duration)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.white.opacity(0.06))
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard store.canChangePlaybackView else { return }
                        store.seek(to: SpatialAnnotationTimelineMath.time(at: value.location.x - 44,
                            width: width, duration: duration), broadcast: false)
                    })
                ForEach(0..<5) { tick in
                    let x = 44 + width * CGFloat(tick) / 4
                    Rectangle().fill(.white.opacity(0.10)).frame(width: 1, height: 80).offset(x: x)
                }
                Capsule().fill(ReplayTheme.orange.opacity(editable ? 0.85 : 0.35))
                    .frame(width: max(endX - startX, 3), height: 18)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                    .offset(x: startX)
                    .gesture(editGesture(.move, width: width))
                    .onTapGesture(perform: onSelect)
                    .help("Drag to move this mark in time")
                    .accessibilityLabel("Move \(mark.label) in time")
                trimHandle(.start, x: startX, width: width)
                trimHandle(.end, x: endX, width: width)
                ForEach(mark.keyframes ?? [], id: \.time) { key in
                    keyHandle(key.time, width: width, duration: duration)
                }
                Rectangle().fill(.white).frame(width: 2, height: 82)
                    .offset(x: 44 + width * CGFloat(store.playhead / duration))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 84)
        .accessibilityElement(children: .contain)
    }

    private func trimHandle(_ handle: SpatialAnnotationTimelineMath.Handle, x: CGFloat,
                            width: CGFloat) -> some View {
        let isStart = handle == .start
        return Capsule().fill(.white).frame(width: 4, height: 24)
            .frame(width: 44, height: 44, alignment: isStart ? .trailing : .leading)
            .contentShape(Rectangle())
            .offset(x: isStart ? x - 44 : x, y: 0)
            .gesture(editGesture(handle, width: width))
            .help(isStart ? "Drag when this mark appears" : "Drag when this mark disappears")
            .accessibilityLabel(isStart ? "Mark in" : "Mark out")
            .accessibilityValue(timestamp(isStart ? window.start : (window.end ?? store.selectedScenario.duration)))
            .accessibilityAdjustableAction { direction in
                guard editable else { return }
                let delta = direction == .increment ? 0.1 : -0.1
                let value = SpatialAnnotationTimelineMath.trim(handle, mark: mark, delta: delta,
                    duration: store.selectedScenario.duration)
                _ = store.setCoachMarkWindow(id: mark.id, start: value.start, end: value.end)
            }
    }

    private func keyHandle(_ time: TimeInterval, width: CGFloat, duration: TimeInterval) -> some View {
        var shown = time
        if let drag, drag.handle == .key(time) { shown = min(max(time + drag.delta, 0), duration) }
        if let drag, drag.handle == .move { shown += window.start - mark.revealTime }
        return Image(systemName: "diamond.fill")
            .font(.system(size: 12, weight: .black)).foregroundStyle(ReplayTheme.cyan)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .offset(x: 22 + width * CGFloat(shown / duration), y: 40)
            .gesture(editGesture(.key(time), width: width))
            .onTapGesture {
                guard store.canChangePlaybackView else { return }
                store.seek(to: time, broadcast: false)
            }
            .help("Pose at \(timestamp(time)) · drag to retime")
            .accessibilityLabel("Position key at \(timestamp(time))")
            .accessibilityAdjustableAction { direction in
                guard editable else { return }
                let destination = min(max(time + (direction == .increment ? 0.1 : -0.1), 0), duration)
                _ = store.retimeCoachMarkKeyframe(id: mark.id, from: time, to: destination)
            }
    }

    private func editGesture(_ handle: SpatialAnnotationTimelineMath.Handle, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard editable else { drag = nil; return }
                if drag == nil {
                    store.setPlaying(false, broadcast: false)
                    drag = Edit(scenarioID: store.selectedScenarioID, view: store.viewMode,
                        mark: mark, playhead: store.playhead, handle: handle)
                }
                guard drag?.handle == handle else { return }
                drag?.delta = Double(value.translation.width / width) * store.selectedScenario.duration
            }
            .onEnded { value in
                if drag?.handle == handle {
                    drag?.delta = Double(value.translation.width / width) * store.selectedScenario.duration
                }
                commitDrag()
            }
    }

    private func commitDrag() {
        guard let edit = drag else { return }
        defer { drag = nil }
        guard editable, edit.scenarioID == store.selectedScenarioID, edit.view == store.viewMode,
              !store.isPlaying, abs(store.playhead - edit.playhead) < CoachMark.keyframeTimeTolerance,
              store.marks.first(where: { $0.id == edit.mark.id }) == edit.mark else { return }
        switch edit.handle {
        case .start, .end:
            let result = SpatialAnnotationTimelineMath.trim(edit.handle, mark: edit.mark, delta: edit.delta,
                duration: store.selectedScenario.duration)
            _ = store.setCoachMarkWindow(id: edit.mark.id, start: result.start, end: result.end)
        case .move:
            let start = SpatialAnnotationTimelineMath.movedStart(mark: edit.mark, delta: edit.delta,
                duration: store.selectedScenario.duration)
            _ = store.retimeCoachMark(id: edit.mark.id, to: start)
        case .key(let time):
            let destination = min(max(time + edit.delta, 0), store.selectedScenario.duration)
            _ = store.retimeCoachMarkKeyframe(id: edit.mark.id, from: time, to: destination)
        }
    }

    private func timestamp(_ time: TimeInterval) -> String { String(format: "%.2fs", time) }
}
