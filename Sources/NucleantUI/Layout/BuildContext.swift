//
//  BuildContext.swift
//  NucleantUI
//
//  The state carried *down* a build pass. A value type: `child(_:_:)` hands a
//  copy to a subtree, so an environment change made inside it can't leak back
//  out to a sibling. The records, the effects and the animations are shared,
//  and they are classes for exactly that reason.
//

@MainActor
public struct BuildContext {

    /// The structural path to the view being built — one index per level.
    /// Moved only by `child(_:_:)` and `move(to:)`, which keep the cursors
    /// below with it.
    private(set) var path: [Int] = []

    /// Where `path` stands among the positions of the tree — see
    /// `RebuildRecords.Cursor`.
    private var recordCursor: RebuildRecords.Cursor?

    /// The node of `dirtyPaths` at `path`; `nil` where no dirty path runs
    /// through it. Stepped with `path`, so a view asks whether anything
    /// under it is dirty without walking the trie from the root.
    private var dirtyCursor: PathTrie<Void>.Node?

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
        effects: EffectQueue,
        animations: AnimationStore,
        records: RebuildRecords,
        dirtyPaths: Set<[Int]> = []
    ) {
        self.environment = environment
        self.effects = effects
        self.animations = animations
        self.records = records
        let trie = PathTrie<Void>()
        for path in dirtyPaths { trie.set((), at: path) }
        self.dirtyPaths = trie
        self.recordCursor = records.cursor(at: [])
        self.dirtyCursor = trie.root
    }

    /// Build a subtree at child slot `index`.
    func child<R>(_ index: Int, _ body: (inout BuildContext) -> R) -> R {
        var sub = self
        sub.path.append(index)
        sub.recordCursor = records.cursor(stepping: recordCursor, into: index, at: sub.path)
        sub.dirtyCursor = dirtyCursor?.child(index)
        return body(&sub)
    }

    /// A copy to keep past this build — a `GeometryReader`'s, for building
    /// its content during placement: without the cursor, which says where
    /// this build stands and no later one. It is found again from the root
    /// when the copy builds.
    var keptPastThisBuild: BuildContext {
        var copy = self
        copy.recordCursor = nil
        return copy
    }

    /// Stand at `path` — a rebuild starting there, a transition's body built
    /// beside the children — with the cursors found for it from the roots.
    mutating func move(to path: [Int]) {
        self.path = path
        recordCursor = records.cursor(at: path)
        dirtyCursor = dirtyPaths.node(at: path)
    }

    /// Whether a state write dirtied exactly `path` this frame — the view
    /// there is where the change originated.
    func isDirty(at path: [Int]) -> Bool {
        if path == self.path { return isDirtyHere }
        return dirtyPaths.value(at: path) != nil
    }

    /// Whether anything at or below `path` was dirtied this frame.
    func isDirty(under path: [Int]) -> Bool {
        if path == self.path { return isDirtyHereOrBelow }
        // The trie only has nodes along dirty paths, so a node existing at
        // `path` means some dirty path runs through or ends there.
        return dirtyPaths.node(at: path) != nil
    }

    /// `isDirty(at: path)`, for this context's own path.
    var isDirtyHere: Bool { dirtyCursor?.value != nil }

    /// `isDirty(under: path)`, for this context's own path.
    var isDirtyHereOrBelow: Bool { dirtyCursor != nil }

    /// Where this context's path stands in the tree: what the view built
    /// here holds as long as it stands — its state — is held there.
    var position: ViewPosition {
        records.position(at: path, cursor: recordCursor)
    }

    /// What stood at this context's path before this rebuild began, if
    /// anything did — `RebuildRecords.candidate(at:)` for `path`, read off
    /// the cursor.
    var candidate: RebuildRecords.Candidate? {
        records.candidate(at: path, cursor: recordCursor)
    }

    /// Whether the child about to be built in slot `index` is new here.
    func isNewChild(at index: Int) -> Bool {
        records.isNewChild(at: index, under: path, cursor: recordCursor)
    }

    /// Keep the standing subtree `candidate` at this context's path, now
    /// standing under `environment`.
    func reuse(_ candidate: RebuildRecords.Candidate) {
        records.reuse(candidate, under: environment)
    }

    /// File `entry` at this context's path.
    func record(_ entry: RebuildRecords.Entry) {
        records.record(entry, at: path, cursor: recordCursor)
    }

    /// What still stands, un-rebuilt, directly under this context's path —
    /// by slot.
    var leftoverChildren: [(Int, ViewNode)] {
        records.leftoverChildren(under: path, cursor: recordCursor)
    }

    /// Bind every `@State` / `@Environment` on `view`, in place, before its
    /// `body` runs — its state held at this context's position. The view
    /// does the walking, through what `@View` generated.
    func bindDynamicProperties<V: View>(of view: inout V) {
        let binder = DynamicPropertyBinder(
            position: position,
            environment: environment,
            path: path,
            owner: ViewIdentity(type: ObjectIdentifier(V.self), viewID: view._viewID)
        )
        view._bindDynamicProperties(binder)
    }
}

/// Deferred work a build pass produced — `onAppear`, `onDisappear` and
/// `onChange` bodies. What each effect keeps between builds — whether it
/// ran, the value it last saw — is on the position of the view that
/// attached it (`ViewPosition`), and goes with it.
@MainActor
final class EffectQueue {
    private var pending: [() -> Void] = []

    /// Every `.onPreferenceChange` standing — checked after each pass that
    /// built, and forgotten with the views that attached them.
    let preferenceObservers = PreferenceObservers()

    /// Whether placement built views this pass — a `GeometryReader`'s
    /// content — so that a pass that only laid out still gets the work that
    /// follows a build.
    private var builtDuringLayout = false

    /// Queue `action` unless the view at `position` has appeared already:
    /// once per appearance, not once per build.
    func onAppear(at position: ViewPosition, _ action: @escaping () -> Void) {
        guard !position.hasAppeared else { return }
        position.hasAppeared = true
        pending.append(action)
    }

    /// Keep `action` to run when the view at `position` leaves.
    func onDisappear(at position: ViewPosition, _ action: @escaping () -> Void) {
        position.disappearing = action
    }

    /// Queue `action` with the value last seen at `position` and `value`, if
    /// they differ — or with `value` twice, the first time, when `initial`.
    /// The action is this build's, so it sees what this build captured.
    func onChange<V: Equatable>(
        at position: ViewPosition,
        of value: V,
        initial: Bool,
        _ action: @escaping (V, V) -> Void
    ) {
        guard let previous = position.observed?.value(as: V.self) else {
            position.observed = Box(value)
            if initial { pending.append { action(value, value) } }
            return
        }
        guard previous != value else { return }
        position.observed = Box(value)
        pending.append { action(previous, value) }
    }

    /// Queue `action` with `value` if it differs from the value worked out
    /// at the last placement, `placed` — or if there was none. Called from
    /// placement, which comes before the queued actions run.
    func onGeometryChange<V: Equatable>(
        _ placed: PlacedValue,
        to value: V,
        _ action: @escaping @MainActor (V) -> Void
    ) {
        if let previous = placed.value?.value(as: V.self), previous == value { return }
        placed.value = Box(value)
        pending.append { action(value) }
    }

    /// Queue `action` with the value worked out at the last placement and
    /// `value`, if they differ — or with `value` twice, the first time.
    func onGeometryTransition<V: Equatable>(
        _ placed: PlacedValue,
        to value: V,
        _ action: @escaping @MainActor (V, V) -> Void
    ) {
        guard let previous = placed.value?.value(as: V.self) else {
            placed.value = Box(value)
            pending.append { action(value, value) }
            return
        }
        guard previous != value else { return }
        placed.value = Box(value)
        pending.append { action(previous, value) }
    }

    func noteBuiltDuringLayout() {
        builtDuringLayout = true
    }

    /// Whether placement built views since this was last asked.
    func takeBuiltDuringLayout() -> Bool {
        defer { builtDuringLayout = false }
        return builtDuringLayout
    }

    /// Hand back the actions queued this pass.
    func endPass() -> [() -> Void] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }

    /// Forget the views at `paths`, which left or were replaced — the
    /// preference observers they attached — and run `disappearing`, their
    /// `onDisappear` actions, with this pass's effects. What else their
    /// effects kept went with their positions.
    func forget(paths: Set<[Int]>, disappearing: [() -> Void]) {
        preferenceObservers.forget(paths: paths)
        pending.append(contentsOf: disappearing)
    }
}


/// What "the same view" means to the builder: the type, and the call site
/// when the view carries one. Hashable so a render node can be keyed by it.
struct ViewIdentity: Hashable {
    let type: ObjectIdentifier
    let viewID: ViewID
}

/// A tree keyed by path components — the paths state writes dirtied this
/// frame (`BuildContext.dirtyPaths`). What the builder asks of them is by
/// *subtree* — is anything under this path dirty — which in a flat set is a
/// scan of every path; here it is one node, found by walking the path.
///
/// Every build steps through it with the path, and a path is as deep as the
/// view tree. So a step costs a scan of a few keys and nothing else: no
/// hashing, and no reference counting. A walk holds each node it passes
/// through unretained, which is sound because the trie owns every node and
/// nothing is removed while a walk is under way.
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
///
/// The entries are filed on the positions of one tree (`ViewPosition`),
/// which stay where they are from one rebuild to the next. Every rebuild
/// takes a new number — a full one, a scoped one, a `GeometryReader`'s
/// during placement, an offscreen render's — and each position carries the
/// number of the rebuild that last built or kept the view there:
///
/// - **Candidate.** An entry from an older rebuild is what stood there
///   before this one.
/// - **Kept.** The position takes this rebuild's number. Nothing below it is
///   touched, whatever the size of the subtree.
/// - **Rebuilt.** Its entry is replaced, with this rebuild's number.
/// - **Left.** A child of a rebuilt position that is still on an older
///   number once the rebuild is over was neither built again nor kept: the
///   view there has left. It is cut out, with everything below it.
///
/// Only the children of rebuilt positions are looked at. A position deep
/// inside a kept subtree carries an older number, and that is harmless:
/// nothing asks until a rebuild reaches its parent.
@MainActor
final class RebuildRecords {

    struct Entry {
        let identity: ViewIdentity
        /// The environment the view was built under. Rebased when the view
        /// is kept under one that differs only in values its subtree never
        /// read (`reuse`), so that a later rebuild from here — a scoped one,
        /// or a `GeometryReader`'s during placement — gets today's values.
        var environment: EnvironmentValues
        /// The environment values read anywhere in this view's subtree
        /// (`EnvironmentReads`) — the only ones a change of which rebuilds
        /// it when its parent re-runs. Only ever grows while the view
        /// stands: a rebuild below adds what it read (`addEnvironmentReads`).
        var environmentReads = EnvironmentKeySet()
        let stackAxis: Axis?
        /// The view built here: rebuilds it in place, and says whether a
        /// freshly built view is equivalent to it.
        let view: RecordedView
        /// The node this position produced — what a rebuild splices out and
        /// what a reuse hands back. A pass-through wrapper (`Optional`, an
        /// `if`) records its child's node as its own; `replaceNode` keeps
        /// that true when the child is rebuilt on its own.
        var node: ViewNode
        /// State this view read while its body ran; each slot has this
        /// view's path among its readers.
        var reads: [any AnyStateStorage]
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

    /// The tree as it stands.
    private let root = ViewPosition(parent: nil, key: 0)

    /// The rebuild under way — bumped by every `beginRebuild`.
    private var session: UInt64 = 0

    /// The positions built in this rebuild, in the order they were filed:
    /// once it is over, each one's children are looked over for views that
    /// left.
    private var rebuilt: [ViewPosition] = []

    /// Where a build stands: its position, found in this rebuild. Moved one
    /// child at a time as the builder descends (`BuildContext.child`), so
    /// finding the candidate and filing the entry each take one step, not a
    /// walk from the root along the path.
    struct Cursor {
        fileprivate let session: UInt64
        let position: ViewPosition
    }

    /// The cursor at `path`, found from the root — the positions on the way
    /// made where missing.
    func cursor(at path: [Int]) -> Cursor {
        Cursor(session: session, position: root.makeDescendant(along: path))
    }

    /// The cursor one step below `parent`, into slot `index` — at `path`.
    /// Found from the root when `parent` is from before this rebuild began.
    func cursor(stepping parent: Cursor?, into index: Int, at path: [Int]) -> Cursor {
        guard let parent, parent.session == session else { return cursor(at: path) }
        return Cursor(session: session, position: parent.position.makeChild(index))
    }

    /// The position at `path`: `cursor`'s, if it is from this rebuild, or
    /// else found from the root — `nil` if there is none.
    private func standing(at path: [Int], cursor: Cursor?) -> ViewPosition? {
        if let cursor, cursor.session == session { return cursor.position }
        return root.descendant(along: path)
    }

    /// The position at `path`, as `standing(at:cursor:)` finds it — made,
    /// with any missing on the way, if there is none.
    func position(at path: [Int], cursor: Cursor?) -> ViewPosition {
        standing(at: path, cursor: cursor) ?? root.makeDescendant(along: path)
    }

    /// Start a rebuild: every entry filed so far becomes what stood before.
    func beginRebuild() {
        session &+= 1
        rebuilt.removeAll(keepingCapacity: true)
    }

    /// What stood at `position` before this rebuild began, if it is still
    /// there to be kept or replaced.
    private func candidate(standingAt position: ViewPosition) -> Candidate? {
        guard position.record != nil, position.session != session else { return nil }
        return Candidate(position: position)
    }

    /// What stood at `path` before this rebuild began, as a handle the
    /// builder can either keep or replace — read off `cursor` when it
    /// stands at `path` in this rebuild.
    func candidate(at path: [Int], cursor: Cursor?) -> Candidate? {
        standing(at: path, cursor: cursor).flatMap { candidate(standingAt: $0) }
    }

    /// Whether nothing stood in slot `index` below `path` — `cursor`'s.
    func isNewChild(at index: Int, under path: [Int], cursor: Cursor?) -> Bool {
        guard let child = standing(at: path, cursor: cursor)?.child(index) else { return true }
        return candidate(standingAt: child) == nil
    }

    /// Read in place on the position: deciding whether to reuse a view
    /// needs a few of its entry's fields, not a copy of the whole entry.
    @MainActor
    struct Candidate {
        fileprivate let position: ViewPosition
        var entry: Entry { position.record! }
        var identity: ViewIdentity { position.record.unsafelyUnwrapped.identity }
        var stackAxis: Axis? { position.record.unsafelyUnwrapped.stackAxis }
        var lazyKey: LazyBuildKey? { position.record.unsafelyUnwrapped.lazyKey }
        var lazyUnits: Int { position.record.unsafelyUnwrapped.lazyUnits }
        var standingNode: ViewNode { position.record.unsafelyUnwrapped.node }

        /// Whether every environment value the subtree read is the one
        /// `environment` holds.
        func readsAgree(with environment: EnvironmentValues) -> Bool {
            let entry = position.record.unsafelyUnwrapped
            return entry.environment.agrees(with: environment, on: entry.environmentReads)
        }

        var environmentReads: EnvironmentKeySet {
            position.record.unsafelyUnwrapped.environmentReads
        }

        /// Whether `view` is equivalent to the view recorded here. Only for a
        /// view of the recorded one's own type — the caller has matched
        /// `identity`, whose type is that type.
        func isEquivalent<V: View>(to view: V) -> Bool {
            withUnsafePointer(to: view) { position.record.unsafelyUnwrapped.view.isEquivalent(to: UnsafeRawPointer($0)) }
        }
    }

    /// Keep the standing subtree `candidate`, now standing under
    /// `environment` — readers, state, `onAppear` marks and all.
    ///
    /// The subtree read none of the values that differ (`readsAgree`), but
    /// its entries still hold them, and a rebuild started from one of them
    /// later would build with the old ones. So each entry takes the new
    /// values of the keys it inherited unchanged.
    func reuse(_ candidate: Candidate, under environment: EnvironmentValues) {
        let position = candidate.position
        position.session = session
        let old = position.record.unsafelyUnwrapped.environment
        if differs(old, environment) {
            var relinked: [ObjectIdentifier: (from: EnvironmentEntry, to: EnvironmentEntry)] = [:]
            rebase(position, from: old, to: environment, relinked: &relinked)
        }
    }

    /// The last pair of environments compared by `differs`, by version, and
    /// the answer: the rows of a `ForEach` are all kept under the same new
    /// environment, having been built under the same old one.
    private var lastDifference: (old: UInt64, new: UInt64, differs: Bool)?

    private func differs(_ old: EnvironmentValues, _ new: EnvironmentValues) -> Bool {
        if let last = lastDifference, last.old == old.version, last.new == new.version {
            return last.differs
        }
        let differs = old.differs(from: new)
        lastDifference = (old.version, new.version, differs)
        return differs
    }

    private func rebase(
        _ position: ViewPosition,
        from old: EnvironmentValues,
        to new: EnvironmentValues,
        relinked: inout [ObjectIdentifier: (from: EnvironmentEntry, to: EnvironmentEntry)]
    ) {
        if var entry = position.record {
            entry.environment = entry.environment.rebased(from: old, to: new, relinked: &relinked)
            position.record = entry
        }
        position.forEachChild { child in
            rebase(child, from: old, to: new, relinked: &relinked)
        }
    }

    /// Environment values read at `path` after its entry was filed — a
    /// rebuild that started there, a `GeometryReader`'s content built during
    /// placement — added to that entry and every one above it, whose
    /// subtrees hold it.
    func addEnvironmentReads(_ keys: EnvironmentKeySet, along path: [Int]) {
        guard !keys.isEmpty else { return }
        var position: ViewPosition? = root
        var depth = 0
        while let current = position {
            if var entry = current.record, !keys.isSubset(of: entry.environmentReads) {
                entry.environmentReads.formUnion(keys)
                current.record = entry
            }
            guard depth < path.count else { return }
            position = current.child(path[depth])
            depth += 1
        }
    }

    /// Take the old entry out of the running, because a fresh build is
    /// replacing it. Its descendants stay candidates.
    func replace(_ candidate: Candidate) -> Entry {
        defer { candidate.position.record = nil }
        return candidate.entry
    }

    /// File `entry` at `path` — `cursor`'s — as this rebuild's.
    func record(_ entry: Entry, at path: [Int], cursor: Cursor?) {
        let position = position(at: path, cursor: cursor)
        position.record = entry
        position.session = session
        rebuilt.append(position)
    }

    func entry(for path: [Int]) -> Entry? { root.descendant(along: path)?.record }

    /// State the view at `path` read after its entry was filed — a
    /// `GeometryReader`'s content, built again during placement — added to
    /// that entry, so the reader registrations go when the view does.
    func addReads(_ reads: [any AnyStateStorage], at path: [Int]) {
        guard !reads.isEmpty, let position = root.descendant(along: path), var entry = position.record else { return }
        for storage in reads where !entry.reads.contains(where: { $0 === storage }) {
            entry.reads.append(storage)
        }
        position.record = entry
    }

    /// A scoped rebuild put `replacement` where `old` stood at `path`. Every
    /// ancestor that recorded `old` as its own node — a wrapper whose
    /// `makeNode` hands back its child's node — now stands for the
    /// replacement; left pointing at `old`, its next reuse would graft the
    /// stale subtree back in.
    func replaceNode(_ old: ViewNode, with replacement: ViewNode, above path: [Int]) {
        var ancestor = root.descendant(along: path)?.parent
        while let position = ancestor {
            guard var entry = position.record, entry.node === old else { return }
            entry.node = replacement
            position.record = entry
            ancestor = position.parent
        }
    }

    func node(for path: [Int]) -> ViewNode? { entry(for: path)?.node }

    /// What still stands, un-rebuilt, directly under `path` — by slot. Asked
    /// by a container once its new children are built: whatever is left is
    /// a child it no longer has.
    func leftoverChildren(under path: [Int], cursor: Cursor?) -> [(Int, ViewNode)] {
        guard let position = standing(at: path, cursor: cursor) else { return [] }
        var leftover: [(Int, ViewNode)] = []
        position.forEachChild { child in
            if let entry = child.record, child.session != session { leftover.append((child.key, entry.node)) }
        }
        return leftover
    }

    /// What a rebuild did not put back.
    struct Departed {
        /// Every view that left, with its path.
        var entries: [([Int], Entry)] = []
        /// The `onDisappear` actions that left with them, to run.
        var disappearing: [() -> Void] = []
        /// The slot nodes their containers were playing exits of — over,
        /// with the containers.
        var exits: [ViewNode] = []

        var isEmpty: Bool { entries.isEmpty && disappearing.isEmpty && exits.isEmpty }
    }

    /// Finish the rebuild: every child of a position built in it that was
    /// neither built nor kept belonged to a view no longer in the tree. Cut
    /// out, and returned with their paths so the caller can release what
    /// they held.
    func endRebuild() -> Departed {
        defer { rebuilt.removeAll(keepingCapacity: true) }
        var departed = Departed()
        for position in rebuilt {
            cutLeftChildren(of: position, into: &departed)
        }
        return departed
    }

    /// Cut out every child of `position` that this rebuild did not build or
    /// keep, adding what it and everything below it held to `departed`.
    ///
    /// A child with no entry of its own — where a container builds the
    /// bodies of its transitions — is looked through: what stands below it
    /// belongs to `position`. It goes once nothing does.
    private func cutLeftChildren(of position: ViewPosition, into departed: inout Departed) {
        var left: [ViewPosition] = []
        position.forEachChild { child in
            if child.record == nil {
                cutLeftChildren(of: child, into: &departed)
                if child.childCount == 0 { left.append(child) }
            } else if child.session != session {
                left.append(child)
            }
        }
        guard !left.isEmpty else { return }
        for child in left {
            child.leave(base: child.path, into: &departed)
            position.removeChild(child.key)
        }
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
