//
//  StateStore.swift
//  NucleantUI
//
import Foundation

/// Type-erased handle on one `@State` slot, so the store can hold slots of
/// mixed value types in one dictionary — and so `Invalidator` can talk about a
/// slot's identity without knowing its value type.
@MainActor
protocol AnyStateStorage: AnyObject {
    /// Bumped on every write.
    var version: UInt32 { get }


    /// Every view that read this slot while its `body` ran, with the key
    /// paths it read through — see `StateReaders`.
    var readers: StateReaders { get set }
}

/// The views that read one state slot, by their positions' handles, with
/// the key paths each read through — `[]` for the whole value, `[\.[3], \.level]` for a read
/// through `$tracks[3].level`.
///
/// A write dirties each reader whose chain overlaps the written one, which
/// is what stops a view whose *inputs* look unchanged from being reused
/// while the state behind its binding moved — and what lets the other rows
/// be reused when it is only row 3 that moved. Readers of the whole value
/// are kept apart, and the others are filed by the first key path of their
/// chain: a write through `[\.[3], \.level]` reaches the readers of the
/// whole value and looks only among those filed under `\.[3]`, not at the
/// reader of every other row.
struct StateReaders {

    /// Readers of the whole value.
    private var whole: Set<PositionHandle> = []

    /// The other readers, by the first key path of their chain, each with
    /// the chains it read through.
    private var byFirstKeyPath: [AnyKeyPath: [PositionHandle: [[AnyKeyPath]]]] = [:]

    /// The first key paths each of those is filed under, to take it out.
    private var firstKeyPaths: [PositionHandle: [AnyKeyPath]] = [:]

    /// `reader` read the slot through `chain`.
    mutating func add(_ reader: PositionHandle, via chain: [AnyKeyPath]) {
        guard let first = chain.first else {
            whole.insert(reader)
            return
        }
        let known = byFirstKeyPath[first]?[reader]
        if let known, known.contains(chain) { return }
        if known == nil {
            firstKeyPaths[reader, default: []].append(first)
        }
        byFirstKeyPath[first, default: [:]][reader, default: []].append(chain)
    }

    /// `reader` is rebuilt or gone: the reads it made are forgotten.
    mutating func remove(_ reader: PositionHandle) {
        whole.remove(reader)
        guard let firsts = firstKeyPaths.removeValue(forKey: reader) else { return }
        for first in firsts {
            byFirstKeyPath[first]?[reader] = nil
            if byFirstKeyPath[first]?.isEmpty == true {
                byFirstKeyPath[first] = nil
            }
        }
    }

    /// Each reader a write through `chain` reaches: one whose chain and the
    /// written one are nested either way. A reader may be handed over more
    /// than once.
    func forEachReader(reachedBy chain: [AnyKeyPath], _ body: (PositionHandle) -> Void) {
        for reader in whole {
            body(reader)
        }
        guard let first = chain.first else {
            // The whole value: every chain is inside it.
            for readers in byFirstKeyPath.values {
                for reader in readers.keys { body(reader) }
            }
            return
        }
        guard let readers = byFirstKeyPath[first] else { return }
        for (reader, chains) in readers
        where chains.contains(where: { $0.starts(with: chain) || chain.starts(with: $0) }) {
            body(reader)
        }
    }

}

/// What a position holds for one piece of a view's state, whatever its
/// value's type: a `StateStorage`, told apart by its class.
@MainActor
class StateSlot {}

/// One `@State` value, living across rebuilds — held by the position of the
/// view that declared it (`ViewPosition.stateSlot`).
@MainActor
final class StateStorage<Value>: StateSlot, AnyStateStorage {

    private(set) var value: Value
    private(set) var version: UInt32 = 0

    /// The view that declared it — dirtied by a write when the value was
    /// read while the tree was placed.
    let owner: PositionHandle

    var readers = StateReaders()

    /// Read while the tree was laid out or drawn, outside any `body` — a
    /// `ScrollView` placing its content at its offset, a `PathShape` or a
    /// `Canvas` closure reading state as it draws. Nothing records such a
    /// reader, so from then on a write rebuilds the view that declared the
    /// state, which builds the node that will be placed again.
    private(set) var isReadDuringPlacement = false

    /// How two values of `Value` compare — see `set(_:via:)`.
    private let isSameValue: EquivalenceWitness

    init(_ value: Value, owner: PositionHandle) {
        self.value = value
        self.owner = owner
        self.isSameValue = equivalenceWitness(for: Value.self)
    }

    /// The single write path — `@State`'s setter and any `Binding` derived from
    /// it both come through here, so neither can bump the version without also
    /// invalidating, or invalidate without bumping.
    ///
    /// `chain` is the key path the write came through, `[]` for the whole
    /// value. A reader is affected when its chain and the written one are
    /// nested either way: a write to `[3].level` reaches a reader of the whole
    /// array and a reader of `[3].level`, not a reader of `[2].level`.
    ///
    /// Only the readers are dirtied — the view that declared the state is not
    /// rebuilt for passing `$value` down — unless the value was read while
    /// the tree was placed (`isReadDuringPlacement`): then the declaring view
    /// is dirtied as well.
    ///
    /// A write of the value already held is no write: nothing is bumped and
    /// nothing is dirtied, as in SwiftUI. "The same" is decided the way view
    /// inputs are (`equivalenceWitness`): `==` for an `Equatable` value,
    /// identity for an object, the bytes for plain data. A value with no way
    /// to tell counts as changed. A `withAnimation` whose writes were all
    /// equal claims no frame, and its completion runs on the next one, as
    /// for a body that wrote nothing.
    func set(_ newValue: Value, via chain: [AnyKeyPath] = []) {
        let isSame = withUnsafePointer(to: value) { old in
            withUnsafePointer(to: newValue) { new in isSameValue(UnsafeRawPointer(old), UnsafeRawPointer(new)) }
        }
        if isSame { return }
        value = newValue
        didChange(via: chain)
    }

    /// A write of one part of the value — `$tracks[3].level`'s, through
    /// `path`, the key paths of `chain` in one. Only that part is compared
    /// with what it was, and it is written where it lies: the rest of the
    /// value is not read out, copied or compared.
    ///
    /// Into an object, the write changes the object and leaves the slot
    /// holding the same one: no write to the slot, as before — what reads
    /// the object's properties is tracked by observation.
    func set<Part>(_ part: Part, at path: WritableKeyPath<Value, Part>, via chain: [AnyKeyPath]) {
        if Value.self is AnyClass {
            var object = value
            object[keyPath: path] = part
            return
        }
        if _areEquivalent(value[keyPath: path], part) { return }
        value[keyPath: path] = part
        didChange(via: chain)
    }

    private func didChange(via chain: [AnyKeyPath]) {
        version &+= 1
        if isReadDuringPlacement, let position = owner.standingPosition {
            Invalidator.shared.invalidate(owner: position)
        }
        // A reader no longer standing has nothing to rebuild.
        readers.forEachReader(reachedBy: chain) { reader in
            if let position = reader.standingPosition { Invalidator.shared.invalidate(owner: position) }
        }
    }

    /// Read during a body evaluation: records the dependency on whatever view
    /// is currently being built. `chain` is the key path the read came
    /// through, `[]` for the whole value.
    func read(via chain: [AnyKeyPath] = []) -> Value {
        noteRead(via: chain)
        return value
    }

    /// The dependency `read(via:)` records, for a reader that takes only a
    /// part of the value.
    func noteRead(via chain: [AnyKeyPath]) {
        if DependencyTracker.shared.isPlacingOutsideABody {
            isReadDuringPlacement = true
            // What was placed drew from it: not to be kept as it is.
            PlacementRecorder.shared.noteDisturbance()
        } else {
            DependencyTracker.shared.recordRead(self, via: chain)
        }
    }

    /// Read with no dependency recorded — for a write's read-modify-write,
    /// which must not make the *writer* a dependent.
    func peek() -> Value { value }
}

/// Attributes each `@State` read to the view whose `body` is running.
///
/// A read has to be attributed to the view being built, and that view is not a
/// parameter of `@State`'s getter — so the builder publishes the identity it is
/// currently working on here, and the getter reports against it. The same shape
/// as `ViewGraphBuilder.currentBuildNode` in TouchBay's older framework.
///
/// Two things come out of a read: the slot learns it has a reader (so a write
/// can dirty that view), and the view's record learns which slots it read (so
/// the registration can be undone when the view is rebuilt or goes away).
@MainActor
final class DependencyTracker {
    static let shared = DependencyTracker()

    private init() {}

    /// One view having its `body` evaluated, and the slots it read so far —
    /// each once, in the order first read.
    private struct Frame {
        let reader: PositionHandle
        var reads: [any AnyStateStorage] = []
    }

    /// The views currently having their `body` evaluated, innermost last.
    private var stack: [Frame] = []

    /// How many layout-and-draw passes are running. A read during one with
    /// no `body` running is a read no view records (see
    /// `StateStorage.isReadDuringPlacement`); one inside a body built
    /// during placement — a `GeometryReader`'s content — is that body's.
    private var placements = 0

    var isPlacingOutsideABody: Bool { placements > 0 && stack.isEmpty }

    func beginPlacement() {
        placements += 1
    }

    func endPlacement() {
        placements -= 1
    }

    /// The view at `reader`'s position begins evaluating: the reads from
    /// here until the matching `pop` are its own.
    func push(_ reader: PositionHandle) {
        stack.append(Frame(reader: reader))
    }

    /// The view at the top is done: the slots it read, handed over once for
    /// its record.
    @discardableResult
    func pop() -> [any AnyStateStorage] {
        stack.removeLast().reads
    }

    func recordRead(_ storage: any AnyStateStorage, via chain: [AnyKeyPath]) {
        guard !stack.isEmpty else { return }
        let top = stack.count - 1
        storage.readers.add(stack[top].reader, via: chain)
        // Read again, most likely the slot read last.
        for read in stack[top].reads.reversed() where read === storage { return }
        stack[top].reads.append(storage)
    }

    /// Whether the view being evaluated has read any slot so far.
    var currentViewHasReads: Bool {
        !(stack.last?.reads.isEmpty ?? true)
    }
}

/// The seam between "some state changed" and "the window redraws".
///
/// Writes name the view that owns the state, so a rebuild can start there
/// instead of at the root. A full rebuild is the fallback for the cases a
/// scoped rebuild can't serve — a resize, or a dirty path the builder has no
/// record for because the tree changed shape.
///
/// Several trees stand at once, a window's each, and their paths are alike:
/// every one starts at its own root. So the work is filed by the tree the
/// written view stands in — by its root position — and each host takes its
/// own (`consume(tree:)`), never another window's. What names no view —
/// `invalidate()`, `requestPlacement()` — is every tree's, and each serves
/// it once.
@MainActor
public final class Invalidator {
    public static let shared = Invalidator()

    /// What one tree has waiting for its next frame.
    struct Work {
        /// Rebuild from the root.
        var full = false
        /// The views to rebuild, by their paths in the tree.
        var paths: Set<[Int]> = []
        /// Lay the tree out and place it again, with nothing to build.
        var placement = false
        /// The transaction the writes were made in — `withAnimation`'s, most
        /// often. `nil` when none was.
        var transaction: Transaction?
    }

    /// Each tree's work, by its root position.
    private var trees: [ObjectIdentifier: Work] = [:]

    /// The requests made of every tree so far, counted, and how many of
    /// them each tree has served: a tree has one to serve while its count
    /// is behind.
    private var everyTree = Requests()
    private var served: [ObjectIdentifier: Requests] = [:]

    private struct Requests: Equatable {
        var fullRebuilds: UInt64 = 0
        var placements: UInt64 = 0
    }

    private init() {}

    /// Invalidate the subtree rooted at the view standing at `position`,
    /// the one that owns the written state or read it.
    ///
    /// A path inside an offscreen tree is dropped: that tree is a snapshot
    /// (`OffscreenRender`), so nothing re-runs for the write, and no host
    /// would ever take it.
    func invalidate(owner position: ViewPosition) {
        let path = position.path
        guard path.first != OffscreenRender.rootIndex else { return }
        let tree = ObjectIdentifier(position.root)
        trees[tree, default: Work()].paths.insert(path)
        noteTransaction(for: tree)
    }

    /// Invalidate the whole tree rooted at `root` — its window resized, or
    /// its safe area moved.
    func invalidate(tree root: ViewPosition) {
        let tree = ObjectIdentifier(root)
        trees[tree, default: Work()].full = true
        noteTransaction(for: tree)
    }

    /// File the transaction the running code is in, if any, with the frame
    /// of `tree` that will serve this write.
    private func noteTransaction(for tree: ObjectIdentifier) {
        guard let current = TransactionScope.current else { return }
        for completion in current.completions {
            completion.isClaimed = true
        }
        if trees[tree]?.transaction == nil {
            trees[tree]?.transaction = current
        } else {
            trees[tree]?.transaction?.merge(current)
        }
    }

    /// Invalidate every tree: each rebuilds from its root on its next frame.
    public func invalidate() {
        everyTree.fullRebuilds &+= 1
    }

    /// Something placed moved without any view changing — a scroll view's
    /// offset under a finger: the next frame lays the trees out and places
    /// them again, and builds nothing for it. The scroll view doesn't know
    /// which tree it is in, so every tree does.
    func requestPlacement() {
        everyTree.placements &+= 1
    }

    /// Take the work waiting for the tree rooted at `root`, and clear it.
    /// A tree's first call finds nothing asked of every tree: it builds from
    /// its root anyway.
    func consume(tree root: ViewPosition) -> Work {
        let tree = ObjectIdentifier(root)
        var work = trees.removeValue(forKey: tree) ?? Work()
        let seen = served[tree] ?? everyTree
        if seen.fullRebuilds != everyTree.fullRebuilds { work.full = true }
        if seen.placements != everyTree.placements { work.placement = true }
        served[tree] = everyTree
        return work
    }

    /// The trees with work waiting, by their roots.
    var waitingTrees: Set<ObjectIdentifier> {
        Set(trees.keys)
    }
}
