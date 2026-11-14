//
//  ViewPosition.swift
//  NucleantUI
//
//  A place in the view tree. There is one per position a view is built at —
//  the root, each child slot below it, a `ForEach` row — and it stays where
//  it is from one rebuild to the next, for as long as something stands
//  there. The builder steps from a position to its children as it descends,
//  so where a view stands is one step from where its parent stands, never a
//  walk from the root.
//
//  A position holds the record of the last build of the view standing there
//  (`RebuildRecords.Entry`) and the number of the rebuild that last built or
//  kept it. Every rebuild takes a new number; a record from an older one is
//  what stood before, and is the candidate the builder compares a new build
//  against. See `RebuildRecords`.
//
//  It also holds what belongs to the view standing there for as long as it
//  is the same view: its state, what its effects keep between builds — an
//  `onAppear`'s mark, an `onChange`'s last value — its animated values, a
//  container's transition slots, and the environment a modifier wrote. A
//  rebuild of the same view keeps them; another view taking the position,
//  or the view leaving, drops them.
//

import Foundation

/// One place in the view tree, kept in place across rebuilds.
final class ViewPosition {
    /// The position this one is a child of; `nil` at the root.
    unowned let parent: ViewPosition?

    /// The slot in the parent.
    let key: Int

    /// The last build of the view standing here; `nil` while a build here
    /// replaces it, and at a place no view is built at itself — where a
    /// container builds the bodies of its transitions.
    var record: RebuildRecords.Entry?

    /// The rebuild that last built or kept the view here.
    var session: UInt64 = 0

    /// The view the state here belongs to — type and call site.
    private var stateOwner: ViewIdentity?

    /// The `@State`, `@Namespace` and `@FocusState` slots of the view
    /// standing here, by the index of the property that declared each.
    /// They stay as long as the view does: another view taking the
    /// position drops them (`release`), and they go with the position
    /// when the view leaves.
    private var stateSlots: [(index: Int, slot: StateSlot)] = []

    // What the effects of the view standing here keep from one build to the
    // next. A modifier is a view of its own, at a position of its own, so a
    // position holds at most one effect; these go as the state does.

    /// Whether the `onAppear` standing here has run, so it runs once per
    /// appearance rather than once per build.
    var hasAppeared = false

    /// The `onDisappear` action standing here — the latest build's, so it
    /// runs with what that build captured.
    var disappearing: (() -> Void)?

    /// The value the modifier standing here last saw — an `onChange`'s, an
    /// `.animation(_:value:)`'s — to compare the next build's against.
    var observed: AnyBox?

    /// What the `onGeometryChange` standing here worked out when it was
    /// last placed. Its own object, made the first time it is asked for:
    /// placement writes it, through the node built here, and the node
    /// cannot hold the position that holds it.
    var placed: PlacedValue {
        if let placedIfMade { return placedIfMade }
        let made = PlacedValue()
        placedIfMade = made
        return made
    }

    private var placedIfMade: PlacedValue?

    // What the animations of the view standing here keep from one build to
    // the next, so that a rebuild goes on from where the last one's values
    // are. They go as the state does.

    /// The animated parameters of the modifier or builtin standing here —
    /// an opacity, a fill and a stroke — by which parameter each is.
    var animatedVectors: [(slot: AnimationStore.Slot, value: AnimatedVector)] = []

    /// The same, for parameters kept as a type of their own.
    var animatedStates: [(slot: AnimationStore.Slot, state: AnyAnimatableDataState)] = []

    /// The `animatableData` of the `Animatable` view, shape or layout
    /// standing here, on its way somewhere.
    var animatableData: AnyAnimatableDataState?

    /// Whether the view standing here is rebuilt next frame — an
    /// `Animatable` one still on its way.
    var rebuildsNextFrame = false

    /// When the `TimelineView` standing here wants its content rebuilt next.
    var nextTimelineDate: Date?

    /// The child slots of the container standing here — an `if`, a
    /// `ForEach` — with a transition standing on them, by slot.
    var transitionSlots: [Int: TransitionSlot] = [:]

    /// What the render nodes of the view standing here are filed under —
    /// a boundary's images, a drawing group's canvas, a texture view's
    /// node. Made the first time it is asked for.
    var renderSlot: RenderSlot {
        if let renderSlotIfMade { return renderSlotIfMade }
        let made = RenderSlot(position: handle)
        renderSlotIfMade = made
        return made
    }

    /// This position as something that must not keep it holds it — a
    /// state slot listing its readers, a render slot. Made the first time
    /// it is asked for; let go of as the position goes.
    var handle: PositionHandle {
        if let handleIfMade { return handleIfMade }
        let made = PositionHandle(self)
        handleIfMade = made
        return made
    }

    private var handleIfMade: PositionHandle?

    private var renderSlotIfMade: RenderSlot?

    /// The slots of the rows of the `ForEach` standing here, by id — kept
    /// for as long as the position, like the rows themselves: a row keeps
    /// its slot, and so its state, while the data moves around it.
    private var rowSlotsIfMade: AnyRowSlots?

    /// The last write the modifier standing here made into the environment
    /// — see `EnvironmentWrite`.
    var environmentWrite: AnyEnvironmentWrite?

    /// The table of row slots for ids of type `ID` — made the first time,
    /// and again for ids of another type, numbering on from the last.
    func rowSlots<ID: Hashable>(_: ID.Type) -> RowSlots<ID> {
        if let standing = rowSlotsIfMade,
           ObjectIdentifier(Swift.type(of: standing)) == ObjectIdentifier(RowSlots<ID>.self) {
            return unsafeDowncast(standing, to: RowSlots<ID>.self)
        }
        let made = RowSlots<ID>(numberingFrom: rowSlotsIfMade?.next ?? 0)
        rowSlotsIfMade = made
        return made
    }

    /// Whether this position was cut out of the tree, with the view that
    /// stood here. A list of positions kept past a rebuild — the rebuilds
    /// `AnimationStore` has to come — passes it by.
    private(set) var hasLeft = false

    // The children, by slot, in no particular order: the slots in `keys`,
    // the positions in `children`, retained by hand. Raw buffers so that
    // reading them is a load and no more — an array stored in a class is
    // retained and released around every read. Most positions have a
    // handful of children, found by scanning `keys`; one with many — a long
    // `ForEach` — gets `indices` as well, so finding one stays a lookup.
    @exclusivity(unchecked) private var keys: UnsafeMutablePointer<Int>?
    @exclusivity(unchecked) private var children: UnsafeMutablePointer<Unmanaged<ViewPosition>>?
    @exclusivity(unchecked) private(set) var childCount = 0
    @exclusivity(unchecked) private var capacity = 0
    private var indices: [Int: Int]?

    private static var indexedAbove: Int { 16 }

    init(parent: ViewPosition?, key: Int) {
        self.parent = parent
        self.key = key
    }

    deinit {
        handleIfMade?.position = nil
        if let children {
            for index in 0..<childCount { children[index].release() }
        }
        keys?.deallocate()
        children?.deallocate()
    }

    /// The path from the root to here, worked out from the parents — for
    /// what is still keyed by path.
    var path: [Int] {
        var path: [Int] = []
        var position = self
        while let parent = position.parent {
            path.append(position.key)
            position = parent
        }
        path.reverse()
        return path
    }

    @inline(__always)
    private func index(of key: Int) -> Int? {
        if let indices { return indices[key] }
        guard let keys else { return nil }
        for index in 0..<childCount where keys[index] == key {
            return index
        }
        return nil
    }

    /// The child in slot `key`, if one is there.
    @inline(__always)
    func child(_ key: Int) -> ViewPosition? {
        index(of: key).map { children.unsafelyUnwrapped[$0].takeUnretainedValue() }
    }

    /// The child in slot `key`, made if none is there.
    func makeChild(_ key: Int) -> ViewPosition {
        if let index = index(of: key) {
            return children.unsafelyUnwrapped[index].takeUnretainedValue()
        }
        let child = ViewPosition(parent: self, key: key)
        if childCount == capacity { grow() }
        keys.unsafelyUnwrapped[childCount] = key
        children.unsafelyUnwrapped[childCount] = Unmanaged.passRetained(child)
        childCount += 1
        if indices != nil {
            indices![key] = childCount - 1
        } else if childCount > Self.indexedAbove {
            var table: [Int: Int] = [:]
            table.reserveCapacity(childCount)
            for index in 0..<childCount { table[keys.unsafelyUnwrapped[index]] = index }
            indices = table
        }
        return child
    }

    private func grow() {
        let newCapacity = max(4, capacity * 2)
        let newKeys = UnsafeMutablePointer<Int>.allocate(capacity: newCapacity)
        let newChildren = UnsafeMutablePointer<Unmanaged<ViewPosition>>.allocate(capacity: newCapacity)
        if let keys, let children {
            newKeys.moveInitialize(from: keys, count: childCount)
            newChildren.moveInitialize(from: children, count: childCount)
            keys.deallocate()
            children.deallocate()
        }
        keys = newKeys
        children = newChildren
        capacity = newCapacity
    }

    /// Cut out the child in slot `key`. The last child moves into its place.
    func removeChild(_ key: Int) {
        guard let index = index(of: key) else { return }
        let keys = keys.unsafelyUnwrapped
        let children = children.unsafelyUnwrapped
        children[index].release()
        let last = childCount - 1
        if index != last {
            keys[index] = keys[last]
            children[index] = children[last]
            indices?[keys[index]] = index
        }
        childCount = last
        indices?[key] = nil
    }

    func forEachChild(_ body: (ViewPosition) -> Void) {
        for index in 0..<childCount {
            body(children.unsafelyUnwrapped[index].takeUnretainedValue())
        }
    }

    /// The position at `path` below this one, or `nil` where the path runs
    /// out of the tree.
    func descendant<Path: Collection<Int>>(along path: Path) -> ViewPosition? {
        var position = self
        for key in path {
            guard let next = position.child(key) else { return nil }
            position = next
        }
        return position
    }

    /// The position at `path` below this one, made with any missing on the
    /// way.
    func makeDescendant<Path: Collection<Int>>(along path: Path) -> ViewPosition {
        var position = self
        for key in path { position = position.makeChild(key) }
        return position
    }

    /// The state slot for property `index` of `owner`, the view standing
    /// here — made from `initialValue` the first time it is asked for, and
    /// again for a property of another type. A view of another identity
    /// gets slots of its own.
    @MainActor
    func stateSlot<Value>(
        _ index: Int,
        of owner: ViewIdentity,
        ownerPath: [Int],
        initialValue: () -> Value
    ) -> StateStorage<Value> {
        if stateOwner != owner {
            stateSlots.removeAll()
            stateOwner = owner
        }
        let type = ObjectIdentifier(StateStorage<Value>.self)
        for position in stateSlots.indices where stateSlots[position].index == index {
            let slot = stateSlots[position].slot
            if ObjectIdentifier(Swift.type(of: slot)) == type {
                return unsafeDowncast(slot, to: StateStorage<Value>.self)
            }
            let made = StateStorage(initialValue(), ownerPath: ownerPath)
            stateSlots[position].slot = made
            return made
        }
        let made = StateStorage(initialValue(), ownerPath: ownerPath)
        stateSlots.append((index, made))
        return made
    }

    /// Drop what the view that stood here kept — its state, what its
    /// effects kept, its animated values, its transition slots, the slot
    /// its render nodes are filed under — for another takes the position; and add what leaves with it, its
    /// `onDisappear` action and the exits its slots were playing, to
    /// `departed`.
    @MainActor
    func release(into departed: inout RebuildRecords.Departed) {
        stateSlots.removeAll()
        stateOwner = nil
        animatedVectors.removeAll()
        animatedStates.removeAll()
        animatableData = nil
        rebuildsNextFrame = false
        nextTimelineDate = nil
        renderSlotIfMade = nil
        environmentWrite = nil
        if let disappearing { departed.disappearing.append(disappearing) }
        takeExits(into: &departed)
        hasAppeared = false
        disappearing = nil
        observed = nil
        placedIfMade = nil
    }

    /// Mark this position and everything below it as gone — cut out of
    /// the tree — take each view off the readers of the state it read, and
    /// collect what leaves with them: each record, with its path — this
    /// position's being `base` — each `onDisappear` action, in the order of
    /// the tree, and the exits their slots were playing.
    @MainActor
    func leave(base: [Int], into departed: inout RebuildRecords.Departed) {
        hasLeft = true
        if let record {
            departed.entries.append((base, record))
            // What it read will not dirty it again.
            if let handleIfMade {
                for storage in record.reads { storage.readers.remove(handleIfMade) }
            }
        }
        if let disappearing { departed.disappearing.append(disappearing) }
        takeExits(into: &departed)
        forEachChild { child in
            child.leave(base: base + [child.key], into: &departed)
        }
    }

    /// Let go of the transition slots, adding the nodes of those on their
    /// way out to `departed`: their exits end with the container.
    @MainActor
    private func takeExits(into departed: inout RebuildRecords.Departed) {
        guard !transitionSlots.isEmpty else { return }
        for slot in transitionSlots.values where slot.isLeaving {
            departed.exits.append(slot.node)
        }
        transitionSlots = [:]
    }
}

/// A position, held by what must not keep it: a state slot's readers, a
/// render slot, an observation scope. The position lets go of it as it
/// goes, and one whose position is gone — or cut out of the tree — stands
/// for nothing. Compared as the object it is.
///
/// Sendable as a token: an observation's change handler, on whichever
/// thread wrote, hands it to the main actor, and only there is it read.
final class PositionHandle: Hashable, @unchecked Sendable {
    /// Cleared by the position's `deinit`, so never left dangling.
    fileprivate(set) unowned(unsafe) var position: ViewPosition?

    fileprivate init(_ position: ViewPosition) {
        self.position = position
    }

    /// The path of the position while it stands in the tree.
    var standingPath: [Int]? {
        guard let position, !position.hasLeft else { return nil }
        return position.path
    }

    static func == (a: PositionHandle, b: PositionHandle) -> Bool { a === b }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// The last write a modifier made into the environment, whatever the
/// modifier's type.
class AnyEnvironmentWrite {}

/// What a modifier wrote into the environment last time: the version of
/// the environment it wrote over, the modifier, what writing read, and the
/// environment that came out. The same write over the same environment is
/// that environment again, version and all — so a kept view below, which
/// read values from it, compares two numbers rather than each value.
final class EnvironmentWrite<Modifier>: AnyEnvironmentWrite {
    let incoming: UInt64
    let modifier: Modifier
    let reads: EnvironmentKeySet
    let outgoing: EnvironmentValues

    init(incoming: UInt64, modifier: Modifier, reads: EnvironmentKeySet, outgoing: EnvironmentValues) {
        self.incoming = incoming
        self.modifier = modifier
        self.reads = reads
        self.outgoing = outgoing
    }
}

/// A `ForEach`'s row slots, whatever its ids' type: where the numbering
/// has got to.
class AnyRowSlots {
    /// The slot the next new id is given. Only ever goes up: a slot a row
    /// stood in, or may still stand in, is never another id's.
    fileprivate(set) var next: Int

    fileprivate init(numberingFrom next: Int) {
        self.next = next
    }
}

/// The child slot of each row of a `ForEach`, by its id — the id itself,
/// so two ids are two rows even when their hashes are the same. A new id
/// gets a slot no row of this `ForEach` has had: the rows are numbered 0,
/// 1, 2 … in the order their ids first came.
final class RowSlots<ID: Hashable>: AnyRowSlots {
    private var slots: [ID: Int] = [:]

    /// The slot of the row for `id`, given one if it is new.
    func slot(for id: ID) -> Int {
        if let slot = slots[id] { return slot }
        let slot = next
        next += 1
        slots[id] = slot
        return slot
    }

    /// The slot `id`'s row has, if it has one.
    func existingSlot(for id: ID) -> Int? { slots[id] }

    /// Forget the ids whose rows are gone from `position` — no position of
    /// their own, no exit playing — once there are well more of them than
    /// the `built` rows, so that a list that has shown many ids keeps only
    /// what it needs. An id kept past its row is harmless: it comes back
    /// to the slot it had, where nothing stands.
    func forgetGone(from position: ViewPosition, built: Int) {
        guard slots.count > 2 * built + 16 else { return }
        slots = slots.filter { _, slot in
            position.child(slot) != nil || position.transitionSlots[slot] != nil
        }
    }
}

/// The value an `onGeometryChange` worked out when it was last placed —
/// shared by the view's position and the node it built.
final class PlacedValue {
    var value: AnyBox?
}
