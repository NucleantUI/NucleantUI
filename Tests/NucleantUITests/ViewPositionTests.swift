//
//  ViewPositionTests.swift
//  NucleantUITests
//
//  The positions the builder files its records on: a position's children
//  behave as a dictionary by slot, at every size and across removals; a
//  rebuild numbered after the last tells what stood before from what it
//  built or kept; and once it is over, what a rebuilt position no longer
//  holds is cut out with everything below it — looked through a place no
//  view is built at itself — while a kept subtree is left as it stands.
//

import Testing
@testable import NucleantUI

/// A title over a row per index — the rows kept while only the title
/// changes, one leaving when the count drops.
@View
struct PositionShelf {
    let title: String
    let count: Int

    var body: some View {
        VStack {
            Text(title)
            ForEach(0..<count, id: \.self) { index in
                let _ = title
                PositionRow(index: index)
            }
        }
    }
}

@View
struct PositionRow {
    let index: Int

    var body: some View {
        Text("\(index)").padding(4)
    }
}

@MainActor
@Suite
struct ViewPositionTests {

    /// A position's children as a dictionary, read through every way in.
    private func contents(_ parent: ViewPosition, keys: some Sequence<Int>) -> [Int: ObjectIdentifier] {
        var result: [Int: ObjectIdentifier] = [:]
        parent.forEachChild { child in
            #expect(result[child.key] == nil, "key \(child.key) twice")
            #expect(child.parent === parent)
            result[child.key] = ObjectIdentifier(child)
        }
        #expect(parent.childCount == result.count)
        for key in keys {
            #expect(parent.child(key).map(ObjectIdentifier.init) == result[key], "child, key \(key)")
        }
        return result
    }

    @Test func childrenBehaveAsADictionaryAtEverySize() {
        var generator = SystemRandomNumberGenerator()
        for round in 0..<40 {
            let parent = ViewPosition(parent: nil, key: 0)
            var model: [Int: ObjectIdentifier] = [:]
            // Small slots for collisions; hash-sized ones as a `ForEach`
            // row's would be (a word wide: narrowed where `Int` is 32 bits).
            let spread = Int(truncatingIfNeeded: 0x1E37_79B9_7F4A_7C15 as UInt64)
            let offset = Int(truncatingIfNeeded: 0x3000_0000_0000_0000 as UInt64)
            let keyRange = round % 2 == 0 ? Array(0..<48) : (0..<48).map { $0 &* spread &- offset }
            for _ in 0..<400 {
                let key = keyRange.randomElement(using: &generator)!
                if Int.random(in: 0..<10, using: &generator) < 6 {
                    let child = parent.makeChild(key)
                    #expect(child.key == key)
                    // Made once, then found.
                    if let known = model[key] { #expect(ObjectIdentifier(child) == known) }
                    model[key] = ObjectIdentifier(child)
                } else {
                    parent.removeChild(key)
                    model[key] = nil
                }
            }
            #expect(contents(parent, keys: keyRange) == model)
        }
    }

    @Test func aPositionKnowsItsPathAndHoldsWhatIsBelowIt() {
        let root = ViewPosition(parent: nil, key: 0)
        weak var middle: ViewPosition?
        weak var below: ViewPosition?
        do {
            let deep = root.makeDescendant(along: [0, 5, 39])
            #expect(deep.path == [0, 5, 39])
            #expect(root.path == [])
            #expect(root.descendant(along: [0, 5, 39]) === deep)
            #expect(root.descendant(along: [0, 5, 38]) == nil)
            #expect(root.makeDescendant(along: [0, 5, 39]) === deep)
            middle = root.descendant(along: [0, 5])
            below = deep
        }
        // Nothing outside the tree holds them: cut out, they are gone.
        root.child(0)!.removeChild(5)
        #expect(middle == nil)
        #expect(below == nil)
        #expect(root.child(0) != nil)
    }

    // MARK: - Rebuilds

    private func entry(at node: ViewNode = ContentNode(content: GroupContent())) -> RebuildRecords.Entry {
        RebuildRecords.Entry(
            identity: ViewIdentity(type: ObjectIdentifier(EmptyView.self), viewID: .unknown),
            environment: EnvironmentValues(),
            stackAxis: nil,
            view: RecordedViewOf(EmptyView()),
            node: node,
            reads: []
        )
    }

    private func file(_ records: RebuildRecords, at path: [Int]) {
        records.record(entry(), at: path, cursor: records.cursor(at: path))
    }

    @Test func whatStoodBeforeIsTheCandidateUntilBuiltOrKept() {
        let records = RebuildRecords()
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        file(records, at: [0, 1])
        file(records, at: [2])
        #expect(records.endRebuild().isEmpty)

        records.beginRebuild()
        let root = records.cursor(at: [])
        #expect(records.candidate(at: [], cursor: root) != nil)
        #expect(!records.isNewChild(at: 0, under: [], cursor: root))
        #expect(records.isNewChild(at: 1, under: [], cursor: root))
        #expect(Set(records.leftoverChildren(under: [], cursor: root).map(\.0)) == [0, 2])

        // Kept: no longer a candidate, and nothing below it is looked at.
        let kept = records.cursor(at: [0])
        records.reuse(records.candidate(at: [0], cursor: kept)!, under: EnvironmentValues())
        #expect(records.candidate(at: [0], cursor: kept) == nil)
        #expect(records.leftoverChildren(under: [], cursor: root).map(\.0) == [2])

        file(records, at: [])
        #expect(records.candidate(at: [], cursor: root) == nil)

        // `[2]` was neither built nor kept: it has left.
        let departed = records.endRebuild()
        #expect(departed.map(\.0) == [[2]])
        #expect(records.entry(for: [2]) == nil)
        #expect(records.entry(for: [0, 1]) != nil)
    }

    @Test func aPlaceWithNoViewOfItsOwnIsLookedThrough() {
        let bodies = TransitionSlot.bodies
        let records = RebuildRecords()
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        file(records, at: [bodies, 3])
        file(records, at: [bodies, 3, 0])
        #expect(records.endRebuild().isEmpty)

        // The body built again: kept where it stands, what it no longer
        // holds gone.
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        file(records, at: [bodies, 3])
        #expect(records.endRebuild().map(\.0) == [[bodies, 3, 0]])
        #expect(records.entry(for: [bodies, 3]) != nil)

        // Not built: gone, and the place it stood in with it.
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        #expect(records.endRebuild().map(\.0) == [[bodies, 3]])
        #expect(records.cursor(at: []).position.child(bodies) == nil)
    }

    // MARK: - State

    private struct Marker {}

    @Test func stateIsHeldByPropertyIndexForItsOwnView() {
        let position = ViewPosition(parent: nil, key: 0)
        let view = ViewIdentity(type: ObjectIdentifier(Int.self), viewID: .unknown)
        let other = ViewIdentity(type: ObjectIdentifier(Marker.self), viewID: .unknown)
        func slot<Value>(_ index: Int, of owner: ViewIdentity, _ value: Value) -> StateStorage<Value> {
            position.stateSlot(index, of: owner, ownerPath: [], initialValue: { value })
        }

        let count = slot(0, of: view, 1)
        let name = slot(1, of: view, "a")
        #expect(slot(0, of: view, 2) === count)
        #expect(slot(0, of: view, 2).peek() == 1)
        #expect(slot(1, of: view, "b") === name)

        // A property of another type at the index: a slot of its own.
        let flag = slot(1, of: view, true)
        #expect(flag.peek() == true)
        #expect(slot(1, of: view, false) === flag)

        // Another view here: its own state, and the first one's is gone.
        #expect(slot(0, of: other, 5).peek() == 5)
        #expect(slot(0, of: view, 3) !== count)
        #expect(slot(0, of: view, 4).peek() == 3)

        position.releaseState()
        #expect(slot(0, of: view, 6).peek() == 6)
    }

    @Test func stateGoesWithItsPosition() {
        let records = RebuildRecords()
        let view = ViewIdentity(type: ObjectIdentifier(Int.self), viewID: .unknown)
        weak var state: StateStorage<Int>?
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        do {
            let position = records.cursor(at: [0]).position
            state = position.stateSlot(0, of: view, ownerPath: [0], initialValue: { 1 })
        }
        _ = records.endRebuild()
        #expect(state != nil)

        // Kept: the state stays.
        records.beginRebuild()
        file(records, at: [])
        records.reuse(records.candidate(at: [0], cursor: records.cursor(at: [0]))!, under: EnvironmentValues())
        _ = records.endRebuild()
        #expect(state != nil)

        // Left: cut out, and its state with it.
        records.beginRebuild()
        file(records, at: [])
        _ = records.endRebuild()
        #expect(state == nil)
    }

    // MARK: - Built views

    @MainActor
    private final class Builder {
        let records = RebuildRecords()
        let effects = EffectQueue()
        let animations = AnimationStore()

        func build(_ view: PositionShelf) -> (node: ViewNode, departed: [([Int], RebuildRecords.Entry)]) {
            records.beginRebuild()
            var context = BuildContext(
                environment: EnvironmentValues(),
                effects: effects,
                animations: animations,
                records: records
            )
            let node = buildNode(view, &context)
            return (node, records.endRebuild())
        }

        func slot(for index: Int) -> Int {
            BuildContext(environment: EnvironmentValues(), effects: effects, animations: animations, records: records)
                .childSlot(for: index)
        }
    }

    private func isRow(_ departed: ([Int], RebuildRecords.Entry)) -> Bool {
        departed.1.identity.type == ObjectIdentifier(PositionRow.self)
    }

    @Test func aRebuildCutsOutWhatLeftAndLeavesWhatWasKept() {
        // Where the rows stand, learned from one leaving.
        let probe = Builder()
        _ = probe.build(PositionShelf(title: "a", count: 3))
        let probed = probe.build(PositionShelf(title: "a", count: 2)).departed
        guard let rowPath = probed.first(where: isRow)?.0 else {
            Issue.record("no row left")
            return
        }
        #expect(rowPath.last == probe.slot(for: 2))
        let rows = Array(rowPath.dropLast())

        let builder = Builder()
        #expect(builder.build(PositionShelf(title: "a", count: 3)).departed.isEmpty)
        let built = (0..<3).map { builder.records.entry(for: rows + [builder.slot(for: $0)])?.node }
        #expect(built.allSatisfy { $0 != nil })
        func standing(_ index: Int) -> ViewNode? {
            builder.records.entry(for: rows + [builder.slot(for: index)])?.node
        }

        // The title changes: the rows are compared and kept where they
        // stand.
        #expect(builder.build(PositionShelf(title: "b", count: 3)).departed.isEmpty)
        for index in 0..<3 { #expect(standing(index) === built[index], "row \(index)") }

        // A row leaves, with everything below it.
        let shrunk = builder.build(PositionShelf(title: "b", count: 2)).departed
        #expect(shrunk.filter(isRow).map(\.0) == [rowPath])
        #expect(shrunk.count > 1)
        #expect(shrunk.allSatisfy { $0.0.starts(with: rowPath) })
        #expect(builder.records.entry(for: rowPath) == nil)
        for index in 0..<2 { #expect(standing(index) === built[index], "row \(index)") }

        // Gone for good: a later rebuild does not find it leaving again.
        #expect(builder.build(PositionShelf(title: "c", count: 2)).departed.isEmpty)

        // Back: built new.
        #expect(builder.build(PositionShelf(title: "c", count: 3)).departed.isEmpty)
        #expect(standing(2) != nil)
        #expect(standing(2) !== built[2])
    }
}
