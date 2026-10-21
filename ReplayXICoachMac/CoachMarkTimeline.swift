import SwiftUI

/// One lane per element. Clips are visibility windows; diamonds are selectable
/// poses. Drag the ruler to scrub, or the clip ends to trim.
struct CoachMarkTimeline: View {
    let state: ReplayXIWireState
    let selectedMarkID: UUID?
    let playhead: Double
    let select: (ReplayXIWireMark) -> Void
    let seek: (Double, Bool) -> Void
    let trim: (ReplayXIWireMark, Double, Double?) -> Void
    let retime: (ReplayXIWireMark, Double, Double) -> Void
    private let labelWidth: CGFloat = 135

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Elements").font(.caption.weight(.semibold)).frame(width: labelWidth, alignment: .leading)
                GeometryReader { geo in
                    Canvas { context, size in
                        for index in 0...10 {
                            let x = size.width * CGFloat(index) / 10
                            context.draw(Text(CoachWorkspace.clock(state.duration * Double(index) / 10))
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary),
                                at: CGPoint(x: min(max(25, x), size.width - 25), y: 10))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { seek(time($0.location.x, width: geo.size.width), false) }
                        .onEnded { seek(time($0.location.x, width: geo.size.width), true) })
                    .help("Drag to scrub")
                }
            }.frame(height: 24)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(state.marks) { mark in lane(mark).id(mark.id) }
                        if state.marks.isEmpty {
                            Text("Draw a mark to add a track.").font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                }
                .frame(height: min(168, max(48, CGFloat(state.marks.count) * 50)))
                .onChange(of: selectedMarkID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Annotation tracks. Drag clip ends to trim. Click diamonds to jump to saved poses.")
    }

    private func time(_ x: CGFloat, width: CGFloat) -> Double {
        CoachWorkspace.timelineTime(x: x, width: width, duration: state.duration)
    }

    private func lane(_ mark: ReplayXIWireMark) -> some View {
        let selected = mark.id == selectedMarkID
        let color: Color = mark.authored ? .secondary : .orange
        return HStack(spacing: 8) {
            Button { select(mark) } label: {
                Label(mark.label.isEmpty ? CoachWorkspace.title(for: mark.kind) : mark.label,
                      systemImage: mark.authored ? "lock" : CoachWorkspace.symbol(for: mark.kind))
                    .font(.caption).lineLimit(1).frame(width: labelWidth, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(mark.label)
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let duration = max(0.01, state.duration)
                let start = min(max(mark.showAt / duration, 0), 1) * width
                let end = min(max((mark.hideAt ?? state.duration) / duration, 0), 1) * width
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                        .contentShape(Rectangle()).onTapGesture { select(mark) }
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(selected ? 0.75 : 0.35))
                        .frame(width: max(2, end - start), height: 20).offset(x: start, y: 2)
                        .onTapGesture { select(mark); seek(mark.showAt, true) }
                        .help("\(CoachWorkspace.clock(mark.showAt)) – \(CoachWorkspace.clock(mark.hideAt ?? state.duration))")
                    if selected, !mark.authored, state.canEdit {
                        trimHandle(mark, start: true, width: width).offset(x: max(0, start - 5))
                        trimHandle(mark, start: false, width: width).offset(x: min(width - 10, end - 5))
                    }
                    ForEach(mark.keyframes, id: \.self) { key in
                        TimelineKeyHandle(time: key, width: width, duration: duration,
                            revision: state.revision, draggable: selected && !mark.authored && state.canEdit,
                            select: { select(mark); seek(key, true) },
                            commit: { value in
                                guard CoachWorkspace.validKeyMove(from: key, to: value,
                                    keys: mark.keyframes, duration: duration) else { return }
                                retime(mark, key, value)
                            })
                        .position(x: min(max(key / duration * width, 11), width - 11), y: 35)
                    }
                    Rectangle().fill(.white).frame(width: 1, height: 46)
                        .offset(x: min(max(playhead / duration, 0), 1) * width).allowsHitTesting(false)
                }
            }.frame(height: 46)
        }
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 4))
    }

    private func trimHandle(_ mark: ReplayXIWireMark, start: Bool, width: CGFloat) -> some View {
        TimelineTrimHandle(time: start ? mark.showAt : mark.hideAt ?? state.duration,
                           width: width, duration: state.duration, revision: state.revision) { value in
            if start {
                let limit = (mark.hideAt ?? state.duration) - 0.5
                guard limit >= 0 else { return }
                trim(mark, max(mark.hideAt.map { $0 - 30 } ?? 0, min(value, limit)), mark.hideAt)
            } else {
                guard state.duration - mark.showAt >= 0.5 else { return }
                trim(mark, mark.showAt, value >= state.duration - 0.001 ? nil :
                    min(state.duration, mark.showAt + 30, max(mark.showAt + 0.5, value)))
            }
        }
        .help(start ? "Drag In point" : "Drag Out point")
        .accessibilityLabel(start ? "Trim annotation In" : "Trim annotation Out")
    }
}

private struct TimelineKeyHandle: View {
    let time: Double
    let width: CGFloat
    let duration: Double
    let revision: UInt64
    let draggable: Bool
    let select: () -> Void
    let commit: (Double) -> Void
    @GestureState private var delta: CGFloat = 0
    @State private var startRevision: UInt64?
    @State private var invalidated = false

    var body: some View {
        Image(systemName: "diamond.fill")
            .font(.system(size: 11)).foregroundStyle(.cyan)
            .frame(width: 24, height: 24).contentShape(Rectangle())
            .offset(x: delta)
            .onTapGesture(perform: select)
            .gesture(DragGesture(minimumDistance: 3)
                .updating($delta) { value, offset, _ in
                    if draggable { offset = value.translation.width }
                }
                .onChanged { _ in
                    if startRevision == nil { startRevision = revision; invalidated = false }
                }
                .onEnded { value in
                    defer { startRevision = nil; invalidated = false }
                    guard draggable, !invalidated, startRevision == revision else { return }
                    commit(CoachWorkspace.timelineTime(
                        x: time / max(0.01, duration) * width + value.translation.width,
                        width: width, duration: duration))
                })
            .onChange(of: revision) { _, next in
                if let startRevision, startRevision != next { invalidated = true }
            }
            .help(draggable ? "Drag pose to retime · click to seek" : "Click to seek to saved pose")
            .accessibilityLabel("Pose at \(CoachWorkspace.clock(time))")
    }
}

private struct TimelineTrimHandle: View {
    let time: Double
    let width: CGFloat
    let duration: Double
    let revision: UInt64
    let commit: (Double) -> Void
    @GestureState private var delta: CGFloat = 0
    @State private var startRevision: UInt64?
    @State private var invalidated = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.9))
            .frame(width: 4, height: 19).frame(width: 10, height: 24)
            .contentShape(Rectangle()).offset(x: delta)
            .gesture(DragGesture(minimumDistance: 2)
                .updating($delta) { value, offset, _ in offset = value.translation.width }
                .onChanged { _ in
                    if startRevision == nil { startRevision = revision; invalidated = false }
                }
                .onEnded { value in
                    defer { startRevision = nil; invalidated = false }
                    guard !invalidated, startRevision == revision else { return }
                    let originalX = time / max(0.01, duration) * width
                    commit(CoachWorkspace.timelineTime(x: originalX + value.translation.width,
                                                       width: width, duration: duration))
                })
            .onChange(of: revision) { _, next in
                if let startRevision, startRevision != next { invalidated = true }
            }
    }
}
