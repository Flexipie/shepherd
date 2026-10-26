import Foundation

/// A unified diff of two texts by line, for showing a settings change before it is written.
enum LineDiff {
    /// Hunks with `context` unchanged lines around each change, headed by `@@ -a,b +c,d @@` as
    /// `diff -u` writes them. Empty when the texts are equal.
    static func unified(from old: String, to new: String, oldName: String, newName: String, context: Int = 3) -> String {
        let a = lines(old), b = lines(new)
        let ops = edits(from: a, to: b)
        guard ops.contains(where: { $0.kind != .same }) else { return "" }

        var out = "--- \(oldName)\n+++ \(newName)\n"
        var index = 0
        while index < ops.count {
            guard let firstChange = ops[index...].firstIndex(where: { $0.kind != .same }) else { break }
            let start = max(index, firstChange - context)
            // The hunk runs until `context * 2` unchanged lines in a row, or the end.
            var end = firstChange, run = 0
            while end < ops.count, run <= context * 2 {
                run = ops[end].kind == .same ? run + 1 : 0
                end += 1
            }
            end -= max(0, run - context)
            let hunk = ops[start..<end]
            let oldStart = hunk.first.map { $0.oldLine } ?? 0
            let newStart = hunk.first.map { $0.newLine } ?? 0
            let oldCount = hunk.filter { $0.kind != .added }.count
            let newCount = hunk.filter { $0.kind != .removed }.count
            out += "@@ -\(oldCount == 0 ? oldStart : oldStart + 1),\(oldCount) +\(newCount == 0 ? newStart : newStart + 1),\(newCount) @@\n"
            for op in hunk {
                switch op.kind {
                case .same: out += " \(op.text)\n"
                case .removed: out += "-\(op.text)\n"
                case .added: out += "+\(op.text)\n"
                }
            }
            index = end
        }
        return out
    }

    private struct Op {
        enum Kind { case same, removed, added }
        let kind: Kind
        let text: String
        /// Lines of the old and new text before this one.
        let oldLine: Int
        let newLine: Int
    }

    private static func lines(_ text: String) -> [String] {
        var result = text.components(separatedBy: "\n")
        if result.last == "" { result.removeLast() }
        return result
    }

    /// Every line of both texts in order, from the standard library's diff.
    private static func edits(from a: [String], to b: [String]) -> [Op] {
        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                ops.append(Op(kind: .removed, text: a[i], oldLine: i, newLine: j)); i += 1
            } else if j < b.count, inserted.contains(j) {
                ops.append(Op(kind: .added, text: b[j], oldLine: i, newLine: j)); j += 1
            } else {
                ops.append(Op(kind: .same, text: a[i], oldLine: i, newLine: j)); i += 1; j += 1
            }
        }
        return ops
    }
}
