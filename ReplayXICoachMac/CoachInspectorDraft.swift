import Foundation

/// Merge independent fields so renaming a mark cannot discard an unsaved
/// height or timing edit. Only conflicting edits to the same field need reload.
struct CoachInspectorDraft: Equatable {
    var label: String
    var startHeight: Double
    var endHeight: Double
    var showAt: Double
    var hideAt: Double
    var hasHide: Bool
    var controlHeight: Double

    init(label: String, startHeight: Double, endHeight: Double, showAt: Double,
         hideAt: Double, hasHide: Bool, controlHeight: Double) {
        self.label = label; self.startHeight = startHeight; self.endHeight = endHeight
        self.showAt = showAt; self.hideAt = hideAt; self.hasHide = hasHide
        self.controlHeight = controlHeight
    }

    init(_ mark: ReplayXIWireMark, duration: Double) {
        self.init(label: mark.label, startHeight: Double(mark.startHeight),
            endHeight: Double(mark.endHeight), showAt: mark.showAt,
            hideAt: mark.hideAt ?? min(duration, mark.showAt + 5),
            hasHide: mark.hideAt != nil, controlHeight: Double(mark.controlPoint?.y ?? 0))
    }

    static func merge(base: Self, local: Self, remote: Self) -> (draft: Self, conflict: Bool) {
        var result = remote
        var conflict = false
        func mergeField<T: Equatable>(_ key: WritableKeyPath<Self, T>,
                                     equal: (T, T) -> Bool = { $0 == $1 }) {
            if !equal(local[keyPath: key], base[keyPath: key]) {
                result[keyPath: key] = local[keyPath: key]
                if !equal(remote[keyPath: key], base[keyPath: key]) && !equal(remote[keyPath: key], local[keyPath: key]) {
                    conflict = true
                }
            }
        }
        mergeField(\.label)
        // Geometry is Float on the wire. Its round-trip must not look like a
        // competing edit when the inspector's sliders use Double.
        mergeField(\.startHeight, equal: { Float($0) == Float($1) })
        mergeField(\.endHeight, equal: { Float($0) == Float($1) })
        mergeField(\.controlHeight, equal: { Float($0) == Float($1) })
        mergeField(\.showAt); mergeField(\.hideAt); mergeField(\.hasHide)
        return (result, conflict)
    }
}
