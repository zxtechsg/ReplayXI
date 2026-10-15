import SwiftUI

/// Compact lanes show timing windows, not just start dots. The selected mark
/// gets its own track so overlap cannot hide its motion keys.
struct CoachMarkTimeline: View {
    let state: ReplayXIWireState
    let selectedMarkID: UUID?
    let select: (ReplayXIWireMark) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width - 8)
            let duration = max(0.01, state.duration)
            ZStack(alignment: .topLeading) {
                ForEach(Array(state.marks.enumerated()), id: \.element.id) { index, mark in
                    let selected = mark.id == selectedMarkID
                    let start = min(max(mark.showAt / duration, 0), 1) * width
                    let end = min(max((mark.hideAt ?? state.duration) / duration, 0), 1) * width
                    let y: CGFloat = selected ? 32 : CGFloat(index % 3) * 8
                    RoundedRectangle(cornerRadius: 3)
                        .fill(mark.authored ? Color.secondary.opacity(0.5) : Color.orange.opacity(selected ? 1 : 0.55))
                        .frame(width: max(6, end - start), height: selected ? 10 : 6)
                        .offset(x: start + 4, y: y)
                        .help("\(mark.label) · \(CoachWorkspace.clock(mark.showAt)) – \(mark.hideAt.map(CoachWorkspace.clock) ?? "end")")
                        .onTapGesture { select(mark) }
                    if selected {
                        ForEach(mark.keyframes, id: \.self) { key in
                            Image(systemName: "diamond.fill").font(.system(size: 8))
                                .foregroundStyle(.cyan)
                                .position(x: min(max(key / duration, 0), 1) * width + 4, y: y + 5)
                                .allowsHitTesting(false)
                        }
                    }
                }
                Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 1, height: 44)
                    .offset(x: min(max(state.playhead / duration, 0), 1) * width + 4)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: selectedMarkID == nil ? 26 : 46)
        .accessibilityLabel("Annotation timing windows. Orange: coach marks. Grey: authored. Cyan: motion keys.")
    }
}
