import Foundation

/// Device-local, committed annotation history for the currently open scenario.
/// Neither gesture samples nor transport/POV changes belong in the undo stack.
/// Bounds cover both stacks together; clear/erase can retain many mark values.
struct ReplayAnnotationEditHistory {
    static let maximumEntries = 32
    static let maximumRetainedMarkValues = 2_048

    private struct Entry {
        let before: [CoachMark]
        let after: [CoachMark]
        let action: String
        var retainedMarkCount: Int { before.count + after.count }
    }

    private(set) var committedMarks: [CoachMark]
    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var undoTitle: String { undoEntries.last.map { "Undo \($0.action)" } ?? "Undo" }
    var redoTitle: String { redoEntries.last.map { "Redo \($0.action)" } ?? "Redo" }
    var retainedMarkCount: Int {
        undoEntries.reduce(0) { $0 + $1.retainedMarkCount }
            + redoEntries.reduce(0) { $0 + $1.retainedMarkCount }
    }

    init(marks: [CoachMark]) { committedMarks = marks }

    mutating func reset(to marks: [CoachMark]) {
        committedMarks = marks
        undoEntries.removeAll(keepingCapacity: true)
        redoEntries.removeAll(keepingCapacity: true)
    }

    mutating func record(_ marks: [CoachMark]) {
        guard committedMarks != marks else { return }
        let action: String
        let previousIDs = Set(committedMarks.map(\.id))
        let currentIDs = Set(marks.map(\.id))
        let removed = previousIDs.subtracting(currentIDs).count
        let added = currentIDs.subtracting(previousIDs).count
        if added > 0, removed == 0 { action = "add" }
        else if removed > 0, added == 0 { action = removed > 1 ? "clear" : "erase" }
        else { action = "edit" }
        undoEntries.append(Entry(before: committedMarks, after: marks, action: action))
        redoEntries.removeAll(keepingCapacity: true)
        committedMarks = marks
        while undoEntries.count > Self.maximumEntries || retainedMarkCount > Self.maximumRetainedMarkValues {
            undoEntries.removeFirst()
        }
    }

    mutating func undo(current marks: [CoachMark]) -> [CoachMark]? {
        // If an external importer changed marks without going through a local
        // commit, never overwrite that state with an unrelated old snapshot.
        guard marks == committedMarks else { reset(to: marks); return nil }
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(entry)
        committedMarks = entry.before
        return entry.before
    }

    mutating func redo(current marks: [CoachMark]) -> [CoachMark]? {
        guard marks == committedMarks else { reset(to: marks); return nil }
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(entry)
        committedMarks = entry.after
        return entry.after
    }
}
