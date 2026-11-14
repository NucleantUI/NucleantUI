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
//  A view's state, what its effects keep and its animated values go with
//  its position, and are dropped for another view — hosted: an animating
//  view or a timeline that left is not built again, and another view in an
//  animating one's place starts from its own value.
//

import Foundation
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

    private func entry(
        at node: ViewNode = ContentNode(content: GroupContent()),
        reads: [any AnyStateStorage] = []
    ) -> RebuildRecords.Entry {
        RebuildRecords.Entry(
            identity: ViewIdentity(type: ObjectIdentifier(EmptyView.self), viewID: .unknown),
            environment: EnvironmentValues(),
            stackAxis: nil,
            view: RecordedViewOf(EmptyView()),
            node: node,
            reads: reads
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
        #expect(departed.entries.map(\.0) == [[2]])
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
        #expect(records.endRebuild().entries.map(\.0) == [[bodies, 3, 0]])
        #expect(records.entry(for: [bodies, 3]) != nil)

        // Not built: gone, and the place it stood in with it.
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        #expect(records.endRebuild().entries.map(\.0) == [[bodies, 3]])
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

        var left = RebuildRecords.Departed()
        position.release(into: &left)
        #expect(left.isEmpty)
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

    // MARK: - Effects

    @Test func whatEffectsKeptIsDroppedForAnotherView() {
        let position = ViewPosition(parent: nil, key: 0)
        var ran = 0
        position.hasAppeared = true
        position.observed = Box(1)
        position.disappearing = { ran += 1 }
        let placed = position.placed
        #expect(position.placed === placed, "made once, then found")

        // Another view takes the position: the one that stood there leaves.
        var left = RebuildRecords.Departed()
        position.release(into: &left)
        for action in left.disappearing { action() }
        #expect(ran == 1)
        #expect(!position.hasAppeared)
        #expect(position.observed == nil)
        #expect(position.disappearing == nil)
        #expect(position.placed !== placed)
        var again = RebuildRecords.Departed()
        position.release(into: &again)
        #expect(again.isEmpty)
    }

    @Test func onDisappearActionsLeaveWithTheirPositions() {
        let records = RebuildRecords()
        var ran: [[Int]] = []
        records.beginRebuild()
        for path in [[], [0], [0, 1], [0, 1, 2], [3]] { file(records, at: path) }
        for path in [[0], [0, 1, 2], [3]] {
            records.cursor(at: path).position.disappearing = { ran.append(path) }
        }
        #expect(records.endRebuild().isEmpty)

        // `[0]` leaves with everything below it; `[3]` is kept.
        records.beginRebuild()
        file(records, at: [])
        records.reuse(records.candidate(at: [3], cursor: records.cursor(at: [3]))!, under: EnvironmentValues())
        let departed = records.endRebuild()
        #expect(departed.entries.map(\.0) == [[0], [0, 1], [0, 1, 2]])
        for action in departed.disappearing { action() }
        #expect(ran == [[0], [0, 1, 2]], "in the order of the tree")

        // Kept, it still has its own.
        records.beginRebuild()
        file(records, at: [])
        for action in records.endRebuild().disappearing { action() }
        #expect(ran == [[0], [0, 1, 2], [3]])
    }

    // MARK: - Animations

    @Test func animatedValuesAreKeptBySlotForTheirView() {
        let store = AnimationStore()
        let position = ViewPosition(parent: nil, key: 0)
        let fill = store.value(at: position, slot: .fill, target: [1, 0, 0, 1], animation: nil)
        #expect(store.value(at: position, slot: .fill, target: [0, 1, 0, 1], animation: nil) === fill)
        #expect(fill.target == [0, 1, 0, 1])
        #expect(store.value(at: position, slot: .stroke, target: [0, 0, 1, 1], animation: nil) !== fill)

        let opacity = store.state(at: position, slot: .opacity, target: 0.5, animation: nil)
        #expect(store.state(at: position, slot: .opacity, target: 0.25, animation: nil) === opacity)
        #expect(opacity.target == 0.25)
        // A value of another type in the slot: one of its own.
        let pair = store.state(at: position, slot: .opacity, target: AnimatablePair(1.0, 2.0), animation: nil)
        #expect(pair.target == AnimatablePair(1.0, 2.0))

        let data = store.animatableData(at: position, target: 3.0, animation: nil)
        #expect(store.animatableData(at: position, target: 4.0, animation: nil) === data)

        // Another view takes the position: everything starts afresh.
        var left = RebuildRecords.Departed()
        position.release(into: &left)
        #expect(store.value(at: position, slot: .fill, target: [1, 0, 0, 1], animation: nil) !== fill)
        #expect(store.animatableData(at: position, target: 3.0, animation: nil) !== data)
    }

    // MARK: - Transitions

    private func slot(_ index: Int) -> TransitionSlot {
        TransitionSlot(index: index, content: ContentNode(content: GroupContent()), effects: [], transition: .opacity)
    }

    private func beginExit(of slot: TransitionSlot, from container: ViewPosition) {
        slot.node.removal = NodeRemoval(
            container: container,
            frame: .zero,
            proposal: .unspecified,
            transform: .identity,
            position: 0,
            startFrame: 0,
            runs: []
        )
    }

    @Test func theExitsOfAContainerThatLeftEndWithIt() {
        let records = RebuildRecords()
        let leaving = slot(1)
        let arriving = slot(2)
        weak var container: ViewPosition?
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        do {
            let standing = records.cursor(at: [0]).position
            beginExit(of: leaving, from: standing)
            standing.transitionSlots = [1: leaving, 2: arriving]
            container = standing
        }
        #expect(records.endRebuild().isEmpty)

        // The container leaves: only the slot on its way out had an exit
        // to end, and nothing the container held keeps it.
        records.beginRebuild()
        file(records, at: [])
        let departed = records.endRebuild()
        #expect(departed.exits.map(ObjectIdentifier.init) == [ObjectIdentifier(leaving.node)])
        let gone = container == nil
        #expect(gone)
    }

    @Test func aContainerPlayingAnExitIsNotKeptByIt() {
        let leaving = slot(1)
        weak var container: ViewPosition?
        do {
            let records = RebuildRecords()
            records.beginRebuild()
            file(records, at: [])
            file(records, at: [0])
            let standing = records.cursor(at: [0]).position
            beginExit(of: leaving, from: standing)
            standing.transitionSlots = [1: leaving]
            container = standing
            _ = records.endRebuild()
        }
        // The tree gone — its host closed — the container went with it,
        // though its slot, held here, points back at it.
        let gone = container == nil
        #expect(gone)
        let pointsAtNothing = leaving.node.removal?.container == nil
        #expect(pointsAtNothing)
    }

    // MARK: - Render nodes

    @Test func renderNodesAreFiledUnderTheViewsOwnSlot() {
        let records = RebuildRecords()
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        file(records, at: [1])
        let first = records.cursor(at: [0]).position.renderSlot
        #expect(records.cursor(at: [0]).position.renderSlot === first, "made once, then found")
        #expect(records.cursor(at: [1]).position.renderSlot !== first)
        #expect(first.pathDescription == "[0]")
        let second = records.cursor(at: [1]).position.renderSlot
        _ = records.endRebuild()

        // Another view in its place: a slot of its own, so nodes of its own.
        var left = RebuildRecords.Departed()
        records.cursor(at: [0]).position.release(into: &left)
        #expect(records.cursor(at: [0]).position.renderSlot !== first)

        // Gone: its slot no longer says where it stood.
        records.beginRebuild()
        file(records, at: [])
        file(records, at: [0])
        _ = records.endRebuild()
        #expect(second.pathDescription != "[1]")
    }

    // MARK: - Readers

    @Test func aHandleStandsForItsPositionWhileItStands() {
        let root = ViewPosition(parent: nil, key: 0)
        let handle: PositionHandle
        do {
            let position = root.makeDescendant(along: [2, 5])
            handle = position.handle
            #expect(position.handle === handle, "made once, then found")
            #expect(handle.standingPath == [2, 5])
        }
        // Gone, it stands for nothing — and does not point at where it was.
        root.removeChild(2)
        #expect(handle.standingPath == nil)
    }

    @Test func aViewThatLeftIsTakenOffWhatItRead() {
        let records = RebuildRecords()
        let storage = StateStorage(1, ownerPath: [])
        func readers() -> [PositionHandle] {
            var found: [PositionHandle] = []
            storage.readers.forEachReader(reachedBy: []) { found.append($0) }
            return found
        }
        records.beginRebuild()
        file(records, at: [])
        records.record(entry(reads: [storage]), at: [0], cursor: records.cursor(at: [0]))
        let reader = records.cursor(at: [0]).position.handle
        storage.readers.add(reader, via: [])
        _ = records.endRebuild()
        #expect(readers() == [reader])

        records.beginRebuild()
        file(records, at: [])
        _ = records.endRebuild()
        #expect(readers().isEmpty)
        #expect(reader.standingPath == nil)
    }

    // MARK: - Built views

    @MainActor
    private final class Builder {
        let records = RebuildRecords()
        let effects = EffectQueue()
        let animations = AnimationStore()

        func build<V: View>(_ view: V) -> (node: ViewNode, departed: [([Int], RebuildRecords.Entry)]) {
            records.beginRebuild()
            var context = BuildContext(
                environment: EnvironmentValues(),
                effects: effects,
                animations: animations,
                records: records
            )
            let node = buildNode(view, &context)
            return (node, records.endRebuild().entries)
        }

        /// The slot of the row for `index` of the `ForEach` at `rows`.
        func slot(for index: Int, under rows: [Int]) -> Int {
            records.cursor(at: rows).position.rowSlots(Int.self).existingSlot(for: index) ?? -1
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
        // A row's view stands under the row (`ForEachRow`), in its slot.
        let slotPath = Array(rowPath.dropLast())
        let rows = Array(slotPath.dropLast())
        #expect(slotPath.last == probe.slot(for: 2, under: rows))

        let builder = Builder()
        #expect(builder.build(PositionShelf(title: "a", count: 3)).departed.isEmpty)
        let built = (0..<3).map { builder.records.entry(for: rows + [builder.slot(for: $0, under: rows), 0])?.node }
        #expect(built.allSatisfy { $0 != nil })
        func standing(_ index: Int) -> ViewNode? {
            builder.records.entry(for: rows + [builder.slot(for: index, under: rows), 0])?.node
        }

        // The title changes: the rows are compared and kept where they
        // stand.
        #expect(builder.build(PositionShelf(title: "b", count: 3)).departed.isEmpty)
        for index in 0..<3 { #expect(standing(index) === built[index], "row \(index)") }

        // A row leaves, with everything below it.
        let shrunk = builder.build(PositionShelf(title: "b", count: 2)).departed
        #expect(shrunk.filter(isRow).map(\.0) == [rowPath])
        #expect(shrunk.count > 1)
        #expect(shrunk.allSatisfy { $0.0.starts(with: slotPath) })
        #expect(builder.records.entry(for: rowPath) == nil)
        for index in 0..<2 { #expect(standing(index) === built[index], "row \(index)") }

        // Gone for good: a later rebuild does not find it leaving again.
        #expect(builder.build(PositionShelf(title: "c", count: 2)).departed.isEmpty)

        // Back: built new.
        #expect(builder.build(PositionShelf(title: "c", count: 3)).departed.isEmpty)
        #expect(standing(2) != nil)
        #expect(standing(2) !== built[2])
    }

    // MARK: - Rows

    @Test func idsThatHashAlikeAreRowsOfTheirOwn() {
        let position = ViewPosition(parent: nil, key: 0)
        let slots = position.rowSlots(Clash.self)
        let one = slots.slot(for: Clash(value: 1))
        let two = slots.slot(for: Clash(value: 2))
        #expect(one != two)
        #expect(slots.slot(for: Clash(value: 1)) == one, "kept while it stands")
        #expect(position.rowSlots(Clash.self) === slots)

        // Ids of another type number on: a slot is never another id's.
        let ints = position.rowSlots(Int.self)
        #expect(ints.slot(for: 1) > max(one, two))
    }

    @Test func rowsWhoseIdsHashAlikeLeaveOnTheirOwn() {
        let builder = Builder()
        #expect(builder.build(ClashingRows(ids: [Clash(value: 1), Clash(value: 2)])).departed.isEmpty)
        let departed = builder.build(ClashingRows(ids: [Clash(value: 2)])).departed
        #expect(departed.filter(isRow).count == 1)
    }

    // MARK: - Environment

    @Test func theSameWriteOverTheSameEnvironmentHandsDownTheSameOne() {
        let builder = Builder()
        let log = EnvironmentLog()
        var reads: [EnvironmentKeySet?] = []
        for (pass, alignment) in [(1, TextAlignment.center), (2, .center), (3, .trailing)] {
            _ = builder.build(WrittenAbove(pass: pass, alignment: alignment, log: log))
            reads.append(builder.records.entry(for: [0])?.environmentReads)
        }
        #expect(log.versions.count == 3)
        #expect(log.versions[1] == log.versions[0], "the same write over the same environment")
        #expect(log.versions[2] != log.versions[1], "another value written")
        // What writing read is read again: a change of it above still
        // builds the modifier again.
        #expect(reads[0] != EnvironmentKeySet())
        #expect(reads[1] == reads[0])
    }
}

/// An id whose hash is every other one's.
struct Clash: Hashable {
    let value: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

/// The environment versions views were built under.
@MainActor
final class EnvironmentLog {
    var versions: [UInt64] = []
}

/// Logs the version of the environment it is built under, and is built
/// again for every `pass`.
@View
struct VersionProbe {
    let pass: Int
    let log: EnvironmentLog

    var body: Never { bodyUnavailable() }
}

extension VersionProbe: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        log.versions.append(context.environment.version)
        return ContentNode(content: GroupContent())
    }
}

/// Writes a line limit worked out from the alignment it is written under:
/// a write that reads.
struct LimitFromAlignment: PrimitiveModifier, Equatable {
    let alignment: TextAlignment

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.lineLimit = environment.multilineTextAlignment == alignment ? 1 : 2
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// A probe under the write.
@View
struct WrittenAbove {
    let pass: Int
    let alignment: TextAlignment
    let log: EnvironmentLog

    var body: some View {
        _ModifierView(content: VersionProbe(pass: pass, log: log), modifier: LimitFromAlignment(alignment: alignment))
    }
}

/// A row per id.
@View
struct ClashingRows {
    let ids: [Clash]

    var body: some View {
        VStack {
            ForEach(ids, id: \.self) { id in
                PositionRow(index: id.value)
            }
        }
    }
}

// MARK: - Hosted

/// A number logged at every value it is built at, on its way up.
@View
struct RisingNumber: Animatable {
    var amount: Double
    let log: Log

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    var body: some View {
        let _ = log("up \(Int(amount.rounded()))")
        Color.blue.frame(width: 10, height: 10)
    }
}

/// The same, of another type — another view in the same place.
@View
struct FallingNumber: Animatable {
    var amount: Double
    let log: Log

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    var body: some View {
        let _ = log("down \(Int(amount.rounded()))")
        Color.red.frame(width: 10, height: 10)
    }
}

/// A rising number while `knobs.isShown`.
@View
struct RisingStage {
    let knobs: Knobs
    let log: Log

    var body: some View {
        VStack {
            if knobs.isShown {
                RisingNumber(amount: Double(knobs.value), log: log)
            }
        }
    }
}

/// A rising number, or a falling one in its place.
@View
struct RisingOrFalling {
    let knobs: Knobs
    let log: Log

    var body: some View {
        AnyView(
            knobs.isShown
                ? AnyView(RisingNumber(amount: Double(knobs.value), log: log))
                : AnyView(FallingNumber(amount: 50, log: log))
        )
    }
}

/// A timeline ticking every hundredth of a second while `knobs.isShown`.
@View
struct TickingStage {
    let knobs: Knobs
    let log: Log

    var body: some View {
        let _ = log("stage")
        VStack {
            if knobs.isShown {
                TimelineView(.periodic(from: .now, by: 0.01)) { _ in
                    let _ = log("tick")
                    Color.green.frame(width: 10, height: 10)
                }
            }
        }
    }
}

/// A count that reads its model, shown while `knobs.isShown`.
@View
struct ObservedStage {
    let knobs: Knobs
    let counter: RowCounter
    let log: Log

    var body: some View {
        let _ = log("stage")
        VStack {
            if knobs.isShown {
                ObservedCount(counter: counter, log: log)
            }
        }
    }
}

@View
struct ObservedCount {
    let counter: RowCounter
    let log: Log

    var body: some View {
        let _ = log("count \(counter.value)")
        Color.blue.frame(width: 10, height: 10)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ObservedPositionTests {

        @Test func aViewThatLeftIsNotRebuiltForWhatItObserved() async {
            let knobs = Knobs()
            let counter = RowCounter(id: 0)
            let log = Log()
            let harness = Harness(ObservedStage(knobs: knobs, counter: counter, log: log))
            #expect(log.take() == ["stage", "count 0"])

            await harness.change { counter.value = 1 }
            #expect(log.take() == ["count 1"], "the view that read it, alone")

            await harness.change { knobs.isShown = false }
            #expect(log.take() == ["stage"])

            // What it read last still tells of a change: nothing to rebuild.
            await harness.change { counter.value = 2 }
            #expect(log.take().isEmpty)
        }
    }

    @MainActor
    @Suite
    struct AnimatedPositionTests {

        /// Rising from 0 towards 100 over a second, a few frames in.
        private func rise(_ knobs: Knobs, _ harness: Harness, _ log: Log) async -> [Int] {
            withAnimation(.linear(duration: 1)) { knobs.value = 100 }
            harness.host.update()
            for _ in 0..<3 { await harness.settle(0.05) }
            return log.take().compactMap { Int($0.dropFirst(3)) }
        }

        @Test func anAnimatingViewThatLeftIsNotBuiltAgain() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(RisingStage(knobs: knobs, log: log))
            #expect(log.take() == ["up 0"])

            let rising = await rise(knobs, harness, log)
            #expect(rising.count > 1)
            #expect((rising.last ?? 100) < 100, "still on its way")

            knobs.isShown = false
            harness.host.update()
            _ = log.take()
            for _ in 0..<5 { await harness.settle(0.05) }
            #expect(log.take().isEmpty)
        }

        @Test func anotherViewInAnAnimatingOnesPlaceStartsAtItsOwnValue() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(RisingOrFalling(knobs: knobs, log: log))
            #expect(log.take() == ["up 0"])

            let rising = await rise(knobs, harness, log)
            #expect((rising.last ?? 100) < 100, "still on its way")

            // Under an animation too: it has nowhere to come from.
            withAnimation(.linear(duration: 1)) { knobs.isShown = false }
            harness.host.update()
            for _ in 0..<5 { await harness.settle(0.05) }
            #expect(log.take() == ["down 50"])
        }

        @Test func aTimelineThatLeftDoesNotTick() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(TickingStage(knobs: knobs, log: log))
            for _ in 0..<3 { await harness.settle(0.03) }
            #expect(log.take().filter { $0 == "tick" }.count > 1)

            knobs.isShown = false
            harness.host.update()
            #expect(log.take() == ["stage"])
            for _ in 0..<4 { await harness.settle(0.03) }
            #expect(log.take().isEmpty)
        }
    }
}
