//
//  BuildContext.swift
//  NucleantUI
//
//  The state carried *down* a build pass. A value type: `child(_:_:)` hands a
//  copy to a subtree, so an environment change made inside it can't leak back
//  out to a sibling. The state store is the one shared thing, and it is a
//  class for exactly that reason.
//

@MainActor
public struct BuildContext {

    /// The structural path to the view being built — one index per level.
    /// `@State` identity is derived from it.
    var path: [Int] = []

    /// The identity of the view whose `makeNode` is running — type and
    /// stamped call site — so a builtin that owns a render node can key it
    /// by the same identity the builder keys reuse by, not by path alone.
    /// Set by `buildNode` just before it asks the view for its node.
    var viewIdentity = ViewIdentity(type: ObjectIdentifier(Never.self), viewID: .unknown)

    var environment: EnvironmentValues

    /// The axis of the innermost enclosing stack, if any. `Spacer` and
    /// `Divider` are the two views whose whole shape depends on it, and they
    /// are built before the stack ever lays out — so it travels down here
    /// rather than being inferred later.
    var stackAxis: Axis?

    /// Set inside a lazy stack or grid, down through the views that dissolve
    /// into its layout: which of its units to build, and the count so far.
    /// See `LazyLayout.swift`.
    var lazyCursor: LazyBuildCursor?

    let store: StateStore

    /// `onAppear` / `onDisappear` actions collected during this pass, run
    /// once the tree is built. Reference-boxed so a copied context still
    /// appends to one list.
    let effects: EffectQueue

    /// The tree's animation clock and animated values.
    let animations: AnimationStore

    /// The context of the change being built — whether what it alters
    /// animates. `.animation(_:value:)` and `.transaction` adjust it for
    /// their subtree.
    var transaction = Transaction()

    /// True while a builtin rebuilds a view that stood at this position
    /// before, as opposed to building one that is new here. Set by
    /// `buildNode` for each builtin's `makeNode`; an `if` or a `ForEach`
    /// only transitions children in and out of a container that stood.
    var isReplacingStandingView = false

    /// Where each view's "how to rebuild me here" entry is filed.
    let records: RebuildRecords

    /// Every path some state write dirtied this frame — owners and readers.
    /// A standing subtree is only reused if none of these fall inside it.
    let dirtyPaths: PathTrie<Void>

    init(
        environment: EnvironmentValues,
        store: StateStore,
        effects: EffectQueue,
        animations: AnimationStore,
        records: RebuildRecords,
        dirtyPaths: Set<[Int]> = []
    ) {
        self.environment = environment
        self.store = store
        self.effects = effects
        self.animations = animations
        self.records = records
        let trie = PathTrie<Void>()
        for path in dirtyPaths { trie.set((), at: path) }
        self.dirtyPaths = trie
    }

    /// Build a subtree at child slot `index`.
    func child<R>(_ index: Int, _ body: (inout BuildContext) -> R) -> R {
        var sub = self
        sub.path.append(index)
        return body(&sub)
    }

    /// Whether a state write dirtied exactly `path` this frame — the view
    /// there is where the change originated.
    func isDirty(at path: [Int]) -> Bool {
        dirtyPaths.value(at: path) != nil
    }

    /// Whether anything at or below `path` was dirtied this frame.
    func isDirty(under path: [Int]) -> Bool {
        // The trie only has nodes along dirty paths, so a node existing at
        // `path` means some dirty path runs through or ends there.
        dirtyPaths.node(at: path) != nil
    }

    /// Bind every `@State` / `@Environment` on `view` before its `body` runs.
    /// Returns the keys bound, so the view's record can release them when the
    /// view goes away. The view does the walking, through what `@View`
    /// generated.
    func bindDynamicProperties<V: View>(of view: V) -> [StateKey] {
        let binder = DynamicPropertyBinder(
            store: store,
            environment: environment,
            path: path,
            viewType: ObjectIdentifier(V.self),
            viewID: view._viewID
        )
        view._bindDynamicProperties(binder)
        return binder.keys.keys
    }
}

/// Deferred work a build pass produced — `onAppear` and `onDisappear`
/// bodies.
@MainActor
final class EffectQueue {
    /// Identities that have already run their `onAppear`, so it fires once per
    /// appearance rather than once per rebuild.
    private var appeared: Set<StateKey> = []
    private var pending: [() -> Void] = []

    /// The `onDisappear` action of every view standing — the latest build's,
    /// so it runs with what that build captured.
    private var disappearing: [StateKey: () -> Void] = [:]

    /// Every `.onPreferenceChange` standing — checked after each pass that
    /// built, and forgotten with the views that attached them.
    let preferenceObservers = PreferenceObservers()

    func onAppear(_ key: StateKey, _ action: @escaping () -> Void) {
        guard !appeared.contains(key) else { return }
        appeared.insert(key)
        pending.append(action)
    }

    func onDisappear(_ key: StateKey, _ action: @escaping () -> Void) {
        disappearing[key] = action
    }

    /// Hand back the actions queued this pass.
    func endPass() -> [() -> Void] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }

    /// Forget the views at `paths`, so one that comes back appears again —
    /// and run their `onDisappear` actions with this pass's effects.
    func forget(paths: Set<[Int]>) {
        preferenceObservers.forget(paths: paths)
        if !appeared.isEmpty {
            appeared = appeared.filter { !paths.contains($0.path) }
        }
        guard !disappearing.isEmpty else { return }
        for (key, action) in disappearing where paths.contains(key.path) {
            disappearing[key] = nil
            pending.append(action)
        }
    }
}


/// What "the same view" means to the builder: the type, and the call site
/// when the view carries one. Hashable so a render node can be keyed by it.
struct ViewIdentity: Hashable {
    let type: ObjectIdentifier
    let viewID: ViewID
}

/// A tree keyed by path components. Everything the builder files is keyed
/// by structural path, and everything it does with those files is by
/// *subtree* — take this one out, put that one back, drop whatever is left.
/// In a flat dictionary each of those is a scan of every key; here each is
/// one pointer, found by walking the path.
///
/// Every build walks it — to find what stood at a path, to file what was
/// built there, to ask whether anything under it is dirty — and a path is as
/// deep as the view tree. So a step costs a scan of a few keys and nothing
/// else: no hashing, and no reference counting. A walk holds each node it
/// passes through unretained, which is sound because the trie owns every
/// node and nothing is removed while a walk is under way.
final class PathTrie<Value> {

    final class Node {
        var value: Value?

        // The children, by path component, in no particular order: the
        // components in `keys`, the nodes in `nodes`, retained by hand. Raw
        // buffers so that reading them is a load and no more — an array
        // stored in a class is retained and released around every read.
        // Most nodes have a handful of children, found by scanning `keys`;
        // one with many — a long `ForEach` — gets `positions` as well, so
        // finding one stays a lookup.
        @exclusivity(unchecked) private var keys: UnsafeMutablePointer<Int>?
        @exclusivity(unchecked) private var nodes: UnsafeMutablePointer<Unmanaged<Node>>?
        @exclusivity(unchecked) private(set) var childCount = 0
        @exclusivity(unchecked) private var capacity = 0
        private var positions: [Int: Int]?

        private static var indexedAbove: Int { 16 }

        deinit {
            removeAllChildren()
            keys?.deallocate()
            nodes?.deallocate()
        }

        @inline(__always)
        private func position(of key: Int) -> Int? {
            if let positions { return positions[key] }
            guard let keys else { return nil }
            for position in 0..<childCount where keys[position] == key {
                return position
            }
            return nil
        }

        /// The child at `key`, unretained — for a walk that only passes
        /// through it.
        @inline(__always)
        func unretainedChild(_ key: Int) -> Unmanaged<Node>? {
            position(of: key).map { nodes.unsafelyUnwrapped[$0] }
        }

        func child(_ key: Int) -> Node? {
            unretainedChild(key)?.takeUnretainedValue()
        }

        /// Put `node` at `key`, in place of any child there.
        func setChild(_ node: Node, at key: Int) {
            let retained = Unmanaged.passRetained(node)
            if let position = position(of: key) {
                nodes.unsafelyUnwrapped[position].release()
                nodes.unsafelyUnwrapped[position] = retained
                return
            }
            if childCount == capacity { grow() }
            keys.unsafelyUnwrapped[childCount] = key
            nodes.unsafelyUnwrapped[childCount] = retained
            childCount += 1
            if positions != nil {
                positions![key] = childCount - 1
            } else if childCount > Self.indexedAbove {
                var index: [Int: Int] = [:]
                index.reserveCapacity(childCount)
                for position in 0..<childCount { index[keys.unsafelyUnwrapped[position]] = position }
                positions = index
            }
        }

        private func grow() {
            let newCapacity = max(4, capacity * 2)
            let newKeys = UnsafeMutablePointer<Int>.allocate(capacity: newCapacity)
            let newNodes = UnsafeMutablePointer<Unmanaged<Node>>.allocate(capacity: newCapacity)
            if let keys, let nodes {
                newKeys.moveInitialize(from: keys, count: childCount)
                newNodes.moveInitialize(from: nodes, count: childCount)
                keys.deallocate()
                nodes.deallocate()
            }
            keys = newKeys
            nodes = newNodes
            capacity = newCapacity
        }

        /// Take out the child at `key`. The last child moves into its place.
        @discardableResult
        func removeChild(at key: Int) -> Node? {
            guard let position = position(of: key) else { return nil }
            let keys = keys.unsafelyUnwrapped
            let nodes = nodes.unsafelyUnwrapped
            let removed = nodes[position].takeRetainedValue()
            let last = childCount - 1
            if position != last {
                keys[position] = keys[last]
                nodes[position] = nodes[last]
                positions?[keys[position]] = position
            }
            childCount = last
            positions?[key] = nil
            return removed
        }

        /// Drop every child, keeping the room they took.
        func removeAllChildren() {
            if let nodes {
                for position in 0..<childCount { nodes[position].release() }
            }
            childCount = 0
            positions = nil
        }

        /// Make this node's children `other`'s — the same nodes, now held by
        /// both.
        func setChildren(from other: Node) {
            removeAllChildren()
            other.forEachChild { key, child in setChild(child, at: key) }
        }

        func forEachChild(_ body: (Int, Node) -> Void) {
            for position in 0..<childCount {
                body(keys.unsafelyUnwrapped[position], nodes.unsafelyUnwrapped[position].takeUnretainedValue())
            }
        }

        /// Every value in this subtree, with its path relative to `base`.
        func collect(base: [Int], into result: inout [([Int], Value)]) {
            if let value { result.append((base, value)) }
            forEachChild { index, child in
                child.collect(base: base + [index], into: &result)
            }
        }
    }

    let root = Node()

    /// The node at `path` below `start`, or `nil` where the path runs out of
    /// the tree.
    static func descend<Path: Collection<Int>>(from start: Node, along path: Path) -> Node? {
        var node = Unmanaged.passUnretained(start)
        for index in path {
            guard let next = node._withUnsafeGuaranteedRef({ $0.unretainedChild(index) }) else { return nil }
            node = next
        }
        return node.takeUnretainedValue()
    }

    func node<Path: Collection<Int>>(at path: Path) -> Node? {
        Self.descend(from: root, along: path)
    }

    /// The node at `path`, created along with any missing ancestors.
    func makeNode<Path: Collection<Int>>(at path: Path) -> Node {
        var node = Unmanaged.passUnretained(root)
        for index in path {
            if let next = node._withUnsafeGuaranteedRef({ $0.unretainedChild(index) }) {
                node = next
            } else {
                let next = Node()
                node._withUnsafeGuaranteedRef { $0.setChild(next, at: index) }
                node = Unmanaged.passUnretained(next)
            }
        }
        return node.takeUnretainedValue()
    }

    func value(at path: [Int]) -> Value? { node(at: path)?.value }

    func set(_ value: Value, at path: [Int]) {
        makeNode(at: path).value = value
    }

    /// Cut the subtree at `path` out and hand it back; `nil` if nothing was
    /// filed there or beneath.
    func detach(at path: [Int]) -> Node? {
        guard let last = path.last else {
            let detached = Node()
            detached.value = root.value
            detached.setChildren(from: root)
            root.value = nil
            root.removeAllChildren()
            return detached
        }
        guard let parent = node(at: path.dropLast()) else { return nil }
        return parent.removeChild(at: last)
    }

    /// Graft `subtree` in at `path`, replacing whatever stood there.
    func attach(_ subtree: Node, at path: [Int]) {
        guard let last = path.last else {
            root.value = subtree.value
            root.setChildren(from: subtree)
            return
        }
        makeNode(at: path.dropLast()).setChild(subtree, at: last)
    }
}

/// One entry per view position: everything needed to rebuild that view in
/// place without its parent re-running, and everything needed to decide
/// that it need not be rebuilt at all.
///
/// Rebuilding from the state's owner *downwards* is what makes a scoped
/// rebuild correct rather than merely cheap: nothing above it re-evaluates,
/// so nothing above it can have changed what it was given. Reuse is the
/// complement, for when a parent *does* re-run: a child it produces that is
/// equivalent to the one already standing — same identity, same inputs, same
/// environment, no dirty state beneath — keeps its subtree, and its body is
/// never asked for.
@MainActor
final class RebuildRecords {

    struct Entry {
        let identity: ViewIdentity
        let environment: EnvironmentValues
        let stackAxis: Axis?
        /// The view built here: rebuilds it in place, and says whether a
        /// freshly built view is equivalent to it.
        let view: RecordedView
        /// The node this position produced — what a rebuild splices out and
        /// what a reuse hands back. A pass-through wrapper (`Optional`, an
        /// `if`) records its child's node as its own; `replaceNode` keeps
        /// that true when the child is rebuilt on its own.
        var node: ViewNode
        /// `@State` / `@Environment` slots this view bound.
        let stateKeys: [StateKey]
        /// State this view read while its body ran; each slot has this
        /// view's path among its readers.
        let reads: [any AnyStateStorage]
        /// Whether this view draws into a render node of its own — see
        /// `RenderBoundaryContent`. Sticky: carried over every rebuild of
        /// the same view at this position.
        var isBoundary = false
        /// The lazy window and starting unit this view was built under, if
        /// it was built inside a lazy container, and how many units it
        /// took — reused only under the same, and then it takes the same.
        var lazyKey: LazyBuildKey? = nil
        var lazyUnits = 0
    }

    /// Entries for the tree as it stands.
    private let live = PathTrie<Entry>()

    /// Entries for the subtree currently being rebuilt, as it stood before,
    /// rooted at that subtree's path. Each is either reused (moved back to
    /// `live`), replaced (a fresh build at the same path), or left over at
    /// the end — a view that vanished.
    private var previous: PathTrie<Entry>.Node?
    private var previousBase: [Int] = []

    /// Start rebuilding the subtree at `path`: everything at or beneath it
    /// becomes a candidate for reuse.
    func beginRebuild(under path: [Int]) {
        previous = live.detach(at: path)
        previousBase = path
    }

    private func previousNode<Path: Collection<Int>>(at path: Path) -> PathTrie<Entry>.Node? {
        guard let previous, path.starts(with: previousBase) else { return nil }
        return PathTrie.descend(from: previous, along: path.dropFirst(previousBase.count))
    }

    /// What stood at `path` before this rebuild began, as a handle the
    /// builder can either keep or replace — one walk of the trie, not three.
    func candidate(at path: [Int]) -> Candidate? {
        guard let node = previousNode(at: path), node.value != nil else { return nil }
        return Candidate(node: node)
    }

    /// Read in place on the trie node: deciding whether to reuse a view
    /// needs a few of its entry's fields, not a copy of the whole entry.
    @MainActor
    struct Candidate {
        fileprivate let node: PathTrie<Entry>.Node
        var entry: Entry { node.value! }
        var identity: ViewIdentity { node.value.unsafelyUnwrapped.identity }
        var stackAxis: Axis? { node.value.unsafelyUnwrapped.stackAxis }
        var lazyKey: LazyBuildKey? { node.value.unsafelyUnwrapped.lazyKey }
        var lazyUnits: Int { node.value.unsafelyUnwrapped.lazyUnits }
        var standingNode: ViewNode { node.value.unsafelyUnwrapped.node }

        func isBuiltUnder(_ environment: EnvironmentValues) -> Bool {
            node.value.unsafelyUnwrapped.environment._isEquivalent(to: environment)
        }

        /// Whether `view` is equivalent to the view recorded here. Only for a
        /// view of the recorded one's own type — the caller has matched
        /// `identity`, whose type is that type.
        func isEquivalent<V: View>(to view: V) -> Bool {
            withUnsafePointer(to: view) { node.value.unsafelyUnwrapped.view.isEquivalent(to: UnsafeRawPointer($0)) }
        }
    }

    /// Keep the standing subtree at `path`: its entries go back to `live`
    /// untouched — readers, state, `onAppear` marks and all.
    func reuse(_ candidate: Candidate, at path: [Int]) {
        if path == previousBase {
            previous = nil
        } else if let parent = previousNode(at: path.dropLast()), let last = path.last {
            parent.removeChild(at: last)
        }
        live.attach(candidate.node, at: path)
    }

    /// Take the old entry at exactly `path` out of the running, because a
    /// fresh build is replacing it. Its descendants stay candidates.
    func replace(_ candidate: Candidate) -> Entry {
        defer { candidate.node.value = nil }
        return candidate.entry
    }

    func record(_ entry: Entry, at path: [Int]) {
        live.set(entry, at: path)
    }

    func entry(for path: [Int]) -> Entry? { live.value(at: path) }

    /// A scoped rebuild put `replacement` where `old` stood at `path`. Every
    /// ancestor that recorded `old` as its own node — a wrapper whose
    /// `makeNode` hands back its child's node — now stands for the
    /// replacement; left pointing at `old`, its next reuse would graft the
    /// stale subtree back in.
    func replaceNode(_ old: ViewNode, with replacement: ViewNode, above path: [Int]) {
        var ancestor = path
        while !ancestor.isEmpty {
            ancestor.removeLast()
            guard let node = live.node(at: ancestor), var entry = node.value, entry.node === old else { return }
            entry.node = replacement
            node.value = entry
        }
    }

    func node(for path: [Int]) -> ViewNode? { live.value(at: path)?.node }

    /// What still stands, un-rebuilt, directly under `path` in the subtree
    /// being rebuilt — by slot. Asked by a container once its new children
    /// are built: whatever is left is a child it no longer has.
    func leftoverChildren(under path: [Int]) -> [(Int, ViewNode)] {
        guard let node = previousNode(at: path) else { return [] }
        var leftover: [(Int, ViewNode)] = []
        node.forEachChild { index, child in
            if let value = child.value { leftover.append((index, value.node)) }
        }
        return leftover
    }

    /// Finish the rebuild: whatever is still `previous` belonged to views that
    /// are no longer in the tree. Returned with their paths so the caller can
    /// release what they held.
    func endRebuild() -> [([Int], Entry)] {
        defer { previous = nil }
        guard let previous else { return [] }
        var departed: [([Int], Entry)] = []
        previous.collect(base: previousBase, into: &departed)
        return departed
    }
}

/// The view a position was built from, as `RebuildRecords` keeps it — to
/// rebuild it in place, and to tell whether the next build of that position
/// is the same view. One object holds the view for both, where two closures
/// would each box a copy of it, and the comparison takes the candidate by
/// pointer rather than boxed as `Any` and cast back.
@MainActor
class RecordedView {
    func rebuild(_ context: inout BuildContext) -> ViewNode {
        fatalError("RecordedView is abstract")
    }

    /// `candidate` points at a view of the recorded view's own type.
    func isEquivalent(to candidate: UnsafeRawPointer) -> Bool {
        fatalError("RecordedView is abstract")
    }
}

@MainActor
final class RecordedViewOf<V: View>: RecordedView {
    let view: V

    init(_ view: V) {
        self.view = view
    }

    override func rebuild(_ context: inout BuildContext) -> ViewNode {
        buildNode(view, &context)
    }

    override func isEquivalent(to candidate: UnsafeRawPointer) -> Bool {
        view._isEquivalent(to: candidate.assumingMemoryBound(to: V.self).pointee)
    }
}
