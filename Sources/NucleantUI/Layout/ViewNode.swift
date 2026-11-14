//
//  ViewNode.swift
//  NucleantUI
//
//  One node of the laid-out tree. State lives on the view's position
//  (`ViewPosition`), not here, so a node is cheap to throw away — and cheap
//  to keep: a subtree whose view came out equivalent on the next build is
//  grafted into the new tree as is (see `buildNode`). A class so `place` can write frames back for hit
//  testing without threading everything through inout, and so that graft is
//  a pointer swap.
//
//  What a node *is* — its layout and drawing — is its content, held by the
//  subclass `ContentNode<C>` in the node itself, its type known there, so
//  every call into it is made for that type. What a node can do for the
//  walks over the tree — be hit, take keys, clip what is under it — is read
//  off the content once, when the node is made, into `traits`.
//

@MainActor
class ViewNode {

    /// What this node can do, read off its content when it was made.
    let traits: NodeTraits

    /// `traits` of this node and of every node below it: a walk looking for
    /// one kind of node passes over a subtree that has none.
    private(set) var subtreeTraits: NodeTraits

    private(set) var children: [ViewNode]

    /// Where this node sits in its parent, so a scoped rebuild can put the
    /// replacement back in the same slot. Weak upward, strong downward — the
    /// tree owns its children.
    private(set) weak var parent: ViewNode?
    private(set) var indexInParent: Int = 0

    /// Where `place` put this node. Absolute window coordinates, in points.
    var frame: Rect = .zero

    /// The transform in effect when it was placed — hit testing has to undo it
    /// to map a window point into the node's own space.
    var transform: Transform = .identity

    /// The proposal it was last placed under — what a removed node is
    /// placed under again while it exits.
    var proposal: ProposedSize = .unspecified

    /// The rect layout last gave it, before any animation moved it — what
    /// the next layout is compared with. See `NodeMotion.swift`.
    var layoutRect: Rect?

    /// Its geometry animation in flight.
    var motion = NodeMotion()

    /// For a node whose subtree places purely: what it was last placed with,
    /// and what it drew then when that is kept — see `PlacementCache.swift`.
    /// Dropped here and above whenever the subtree changes.
    var placed: PlacementRecord?

    /// The `.transition` of the view this node stands for, carried up
    /// through the modifiers around it to the container that inserts or
    /// removes it.
    var transitionTrait: AnyTransition?

    /// Set on a container's slot node whose child was removed, while its
    /// transition plays the exit: it is drawn, but neither laid out nor hit.
    var removal: NodeRemoval? {
        didSet {
            let leaving = removal != nil
            guard leaving != isLeaving else { return }
            isLeaving = leaving
            dropPlacementsUpwards()
            // Out of its parent's layout, or back in it.
            parent?.layoutChildrenChanged()
        }
    }

    /// Whether `removal` is set — what the walks over children ask, kept as
    /// a flag so asking doesn't copy the removal out.
    private(set) var isLeaving = false

    /// The path of the view whose build made this node — as opposed to one
    /// that only handed a child's node on (an `if`, a view's `body`).
    /// Motion is inherited only by the node's maker.
    var ownerPath: [Int]?

    /// The element of a lazy container's `ForEach` this node is part of —
    /// see `LazyLayout.swift`.
    var lazyTag: LazyElementTag?

    /// Set on a `Section`'s header or footer, for a lazy container that
    /// pins them.
    var sectionTag: SectionTag?

    /// What `.gridCellColumns` and its kin said about the view this node
    /// stands for, carried up through the modifiers around it to the
    /// `Grid` that lays it out.
    var gridCellTraits: GridCellTraits?

    /// What `.layoutValue(key:value:)` set on the view this node stands
    /// for, carried up the same way, for the custom `Layout` that reads it.
    var layoutValues: LayoutValues?

    /// What this subtree reduced to for each preference key asked about so
    /// far — see `PreferenceKey.swift`. Dropped with the measurements.
    var preferenceCache: [ObjectIdentifier: AnyBox] = [:]

    /// Measurements taken so far, keyed by the proposal that produced them.
    ///
    /// Layout asks the same question repeatedly: a stack measures every child
    /// to decide the run, then `place` measures them again to position them,
    /// and each level above repeats that for its whole subtree. Uncached, a
    /// 195-node tree took 567 `sizeThatFits` calls.
    ///
    /// A node is only kept across passes when nothing that feeds its size
    /// changed — same view value, same environment, no dirty state below —
    /// so an entry stays valid for as long as the node does. What can grow
    /// is the *number* of proposals a long-lived node has seen (every window
    /// size during a drag-resize), hence the cap.
    private var measurements = MeasurementCache()
    /// `flexibility(along:)` walks the subtree; cached alongside the sizes
    /// and dropped with them, one for each axis.
    private var horizontalFlexibility: LayoutPriorityClass?
    private var verticalFlexibility: LayoutPriorityClass?

    /// `layoutChildren`, worked out once and kept until it changes.
    private var flattenedChildren: [ViewNode]?

    /// What the content keeps between passes, by its own type: a stack's
    /// last run and the order it offers its children space in
    /// (`StackRunCache`), a shape's last path (`ShapePathCache`). Dropped
    /// with the measurements, and when the children change.
    var layoutCache: AnyObject?

    fileprivate init(traits: NodeTraits, children: [ViewNode]) {
        self.traits = traits
        self.children = children
        var subtree = traits
        for child in children { subtree.formUnion(child.subtreeTraits) }
        self.subtreeTraits = subtree
        if PerfTrace.isEnabled { PerfTrace.nodesBuilt += 1 }
        for (index, child) in children.enumerated() {
            child.parent = self
            child.indexInParent = index
        }
    }

    /// Swap `replacement` in for the child at `index` — how a scoped rebuild
    /// grafts a freshly built subtree onto the tree that is still standing.
    func replaceChild(at index: Int, with replacement: ViewNode) {
        guard children.indices.contains(index) else { return }
        // Dropped first, so the array is no longer shared when it is written.
        layoutChildrenChanged()
        children[index] = replacement
        replacement.parent = self
        replacement.indexInParent = index
        subtreeTraitsChanged()
        dropPlacementsUpwards()
    }

    /// What this node and every node above it kept of their last placement
    /// was drawn from a subtree that changed.
    func dropPlacementsUpwards() {
        var node: ViewNode? = self
        while let current = node {
            current.placed = nil
            node = current.parent
        }
    }

    /// Work `subtreeTraits` out again from the children, here and above,
    /// as far up as it changes.
    private func subtreeTraitsChanged() {
        var node: ViewNode? = self
        while let current = node {
            var subtree = current.traits
            for child in current.children { subtree.formUnion(child.subtreeTraits) }
            guard subtree != current.subtreeTraits else { return }
            current.subtreeTraits = subtree
            node = current.parent
        }
    }

    // MARK: - The content

    /// The content, as an existential — boxed on each access, for the few
    /// questions asked of it by its type or of one of its abilities a trait
    /// says it has.
    var content: any NodeContent { fatalError("ViewNode is abstract") }

    /// The content, if it is a `T` — asked of the content where it is
    /// stored, without boxing it as `content` does.
    func content<T>(as type: T.Type) -> T? { nil }

    /// The content's answers, made for its type by `ContentNode`.
    fileprivate func contentSizeThatFits(_ proposal: ProposedSize) -> Size { fatalError("ViewNode is abstract") }

    fileprivate func contentPlace(in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        fatalError("ViewNode is abstract")
    }

    fileprivate func contentFlexibility(along axis: Axis) -> LayoutPriorityClass { fatalError("ViewNode is abstract") }

    /// The children in paint order, when the content says it isn't
    /// `children` — see `NodeContent.hitTestOrder`.
    func contentHitTestOrder() -> [ViewNode]? { nil }

    /// The content's value for preference `key` — see `NodeContent.preference`.
    func contentPreference<K: PreferenceKey>(_ key: K.Type, below: K.Value?) -> K.Value? { below }

    /// True when the node contributes its children to the parent's layout
    /// rather than laying them out itself — see `NodeContent.isTransparent`.
    var isTransparent: Bool { traits.contains(.transparent) }

    /// Whether this node, swapped in for `old`, gives every size `old` was
    /// asked for and is as flexible, as the same kind of node — so that
    /// nothing above, whose sizes were worked out from `old`'s, measures
    /// differently. The sizes it is asked here are ones the next pass would
    /// ask anyway. Only as good as `old`'s answers are complete: one that
    /// dropped an answer to make room says no.
    ///
    /// Asked outside a pass, so only of subtrees whose kinds place purely,
    /// which measure purely too: no custom `Layout` running code of the
    /// app's, no lazy container building rows.
    func measuresLike(_ old: ViewNode) -> Bool {
        guard !subtreeTraits.contains(.placesImpurely), !old.subtreeTraits.contains(.placesImpurely),
              old.measurements.isComplete,
              traits == old.traits, !isTransparent,
              gridCellTraits == old.gridCellTraits,
              lazyTag == old.lazyTag, sectionTag == old.sectionTag,
              layoutValues == nil, old.layoutValues == nil,
              flexibility(along: .horizontal) == old.flexibility(along: .horizontal),
              flexibility(along: .vertical) == old.flexibility(along: .vertical)
        else { return false }
        var same = true
        old.measurements.forEach { proposal, size in
            if same, sizeThatFits(proposal) != size { same = false }
        }
        return same
    }

    /// After a child below was swapped for one that measures like it
    /// (`measuresLike(_:)`): every size cached here and above still holds,
    /// but what was reduced from the old subtree's preferences does not. A
    /// custom layout above keeps a cache of its subviews, which is told
    /// they changed the usual way.
    func invalidatePreferencesUpwards() {
        var node: ViewNode? = self
        while let current = node {
            if current.traits.contains(.layoutCacheOwner) {
                current.invalidateMeasurementsUpwards()
                return
            }
            current.preferenceCache.removeAll(keepingCapacity: true)
            node = current.parent
        }
    }

    /// Discard measurements that the swap above may have falsified.
    ///
    /// The new subtree starts with an empty cache of its own, but every
    /// ancestor cached a size that was computed *from* the old one — a stack
    /// that measured its run, the frame above it, and so on to the root.
    func invalidateMeasurementsUpwards() {
        var node: ViewNode? = self
        while let current = node {
            current.measurements.removeAll()
            current.horizontalFlexibility = nil
            current.verticalFlexibility = nil
            current.layoutCache = nil
            current.placed = nil
            // Preferences reduced from the old subtree, and a custom
            // layout's cache built from it, are stale the same way.
            current.preferenceCache.removeAll(keepingCapacity: true)
            if current.traits.contains(.layoutCacheOwner) {
                (current.content as? LayoutCacheOwner)?.subviewsChanged()
            }
            node = current.parent
        }
    }

    /// Children as the layout sees them: transparent nodes (`Group`, a
    /// `TupleView`, `ForEach`) dissolve into their own children, so a stack
    /// treats a group's contents as its own siblings — SwiftUI's rule.
    ///
    /// Asked by every layout pass of every container, several times, so it
    /// is worked out once and kept until it changes (`layoutChildrenChanged`);
    /// the usual case — nothing to dissolve, nothing leaving — is `children`
    /// as it is.
    var layoutChildren: [ViewNode] {
        if let flattenedChildren { return flattenedChildren }
        var isFlat = true
        for child in children where child.isLeaving || child.isTransparent {
            isFlat = false
            break
        }
        let result: [ViewNode]
        if isFlat {
            result = children
        } else {
            var flattened: [ViewNode] = []
            flattened.reserveCapacity(children.count)
            for child in children where !child.isLeaving {
                if child.isTransparent {
                    flattened.append(contentsOf: child.layoutChildren)
                } else {
                    flattened.append(child)
                }
            }
            result = flattened
        }
        flattenedChildren = result
        return result
    }

    /// What `layoutChildren` answers here may have changed: a child was
    /// replaced, came or went from layout, or did so inside a transparent
    /// child — whose layout children are this node's too, and so on up
    /// through the transparent nodes above.
    private func layoutChildrenChanged() {
        var node: ViewNode? = self
        while let current = node {
            current.flattenedChildren = nil
            current.layoutCache = nil
            guard current.isTransparent else { return }
            node = current.parent
        }
    }

    /// The single child a modifier node wraps — the first of
    /// `layoutChildren`, found without flattening the rest.
    ///
    /// A modifier applied to a multi-child `Group` takes the first child only;
    /// SwiftUI would distribute the modifier over each. Worth knowing, but not
    /// worth a second layout mode — write the modifier inside the group.
    var singleChild: ViewNode? {
        for child in children where !child.isLeaving {
            if !child.isTransparent { return child }
            if let inner = child.singleChild { return inner }
        }
        return nil
    }

    /// How this node competes for space in a stack — see `NodeContent`.
    func flexibility(along axis: Axis) -> LayoutPriorityClass {
        switch axis {
        case .horizontal:
            if let cached = horizontalFlexibility { return cached }
            let result = contentFlexibility(along: axis)
            horizontalFlexibility = result
            return result
        case .vertical:
            if let cached = verticalFlexibility { return cached }
            let result = contentFlexibility(along: axis)
            verticalFlexibility = result
            return result
        }
    }

    func sizeThatFits(_ proposal: ProposedSize) -> Size {
        if let cached = measurements.size(for: proposal) { return cached }
        if PerfTrace.isEnabled { PerfTrace.sizeCalls += 1 }
        let size = contentSizeThatFits(proposal)
        measurements.insert(size, for: proposal)
        return size
    }

    /// Position this node in `rect`.
    ///
    /// `proposal` is the proposal that *produced* `rect`, carried alongside it
    /// rather than re-derived from `rect.size`. A node whose size is a function
    /// of its proposal — `.relativeSize`, say — would otherwise have that
    /// function applied a second time to its own output: a 82% fill measured at
    /// 541pt would be re-measured against 541 and come out 443. SwiftUI threads
    /// the proposal through placement for the same reason.
    func place(
        in rect: Rect,
        proposal: ProposedSize,
        context: DrawContext,
        into list: inout DisplayList
    ) {
        let store = AnimationStore.current
        // A view leaving just before this one among its parent's children
        // is drawn first, under it.
        if let store, store.hasExits {
            placeLeavingBefore(context: context, store: store, into: &list)
        } else if !subtreeTraits.contains(.placesImpurely), !context.freezesMotion {
            // Drawn from what it is placed with alone: what it drew the
            // last time, when that is what it would draw.
            PlacementRecorder.shared.place(self, in: rect, proposal: proposal, context: context, into: &list) { list in
                placeFresh(in: rect, proposal: proposal, context: context, store: store, into: &list)
            }
            return
        }
        placeFresh(in: rect, proposal: proposal, context: context, store: store, into: &list)
    }

    /// Position this node in `rect` and draw it, without asking whether what
    /// it drew last time would do.
    private func placeFresh(
        in rect: Rect,
        proposal: ProposedSize,
        context: DrawContext,
        store: AnimationStore?,
        into list: inout DisplayList
    ) {
        var rect = rect
        var context = context
        frame = rect
        if let store, !context.freezesMotion {
            (frame, rect) = animate(rect, context: &context, store: store)
        }
        transform = context.transform
        self.proposal = proposal
        contentPlace(in: rect, proposal: proposal, context: context, into: &list)
        if let store, store.hasExits {
            placeLeavingChildren(context: context, store: store, into: &list)
        }
    }
}

/// The sizes a node gave, by the proposal that asked: the last four in the
/// node itself, found by comparing — most nodes are asked one to three
/// proposals in a pass, so most never hash one or allocate — and the ones
/// before them in a table, so a node a stack asks from both ends, at a
/// share and again while placing still finds every answer it gave. The
/// table is emptied at sixteen, as the whole cache once was.
struct MeasurementCache {
    private var proposals = (ProposedSize.unspecified, ProposedSize.unspecified, ProposedSize.unspecified, ProposedSize.unspecified)
    private var sizes = (Size.zero, Size.zero, Size.zero, Size.zero)
    /// How many of the four slots hold an answer, and which one the next
    /// answer takes once all do.
    private var count = 0
    private var next = 0
    private var older: [ProposedSize: Size]?
    /// False once an answer was dropped to make room: then what it holds
    /// is not every question it was asked.
    private(set) var isComplete = true

    func size(for proposal: ProposedSize) -> Size? {
        if count > 0, proposals.0 == proposal { return sizes.0 }
        if count > 1, proposals.1 == proposal { return sizes.1 }
        if count > 2, proposals.2 == proposal { return sizes.2 }
        if count > 3, proposals.3 == proposal { return sizes.3 }
        return older?[proposal]
    }

    /// File `size` for `proposal`, which has no answer yet. With the four
    /// slots full, the oldest of them moves to the table.
    mutating func insert(_ size: Size, for proposal: ProposedSize) {
        let slot: Int
        if count < 4 {
            slot = count
            count += 1
        } else {
            slot = next
            next = (next + 1) & 3
            let evicted: (ProposedSize, Size)
            switch slot {
            case 0: evicted = (proposals.0, sizes.0)
            case 1: evicted = (proposals.1, sizes.1)
            case 2: evicted = (proposals.2, sizes.2)
            default: evicted = (proposals.3, sizes.3)
            }
            if older == nil { older = [:] }
            if older!.count >= 16 {
                older!.removeAll(keepingCapacity: true)
                isComplete = false
            }
            older![evicted.0] = evicted.1
        }
        switch slot {
        case 0: (proposals.0, sizes.0) = (proposal, size)
        case 1: (proposals.1, sizes.1) = (proposal, size)
        case 2: (proposals.2, sizes.2) = (proposal, size)
        default: (proposals.3, sizes.3) = (proposal, size)
        }
    }

    mutating func removeAll() {
        count = 0
        next = 0
        older?.removeAll(keepingCapacity: true)
        isComplete = true
    }

    /// Every answer it holds, with the proposal that asked.
    func forEach(_ body: (ProposedSize, Size) -> Void) {
        if count > 0 { body(proposals.0, sizes.0) }
        if count > 1 { body(proposals.1, sizes.1) }
        if count > 2 { body(proposals.2, sizes.2) }
        if count > 3 { body(proposals.3, sizes.3) }
        older?.forEach { body($0.key, $0.value) }
    }
}

/// A node with its content: the content stored in the node, and every call
/// into it made for its type.
@MainActor
final class ContentNode<C: NodeContent>: ViewNode {
    let nodeContent: C

    init(content: C, children: [ViewNode] = []) {
        self.nodeContent = content
        super.init(traits: NodeTraits(of: content), children: children)
    }

    override var content: any NodeContent { nodeContent }

    override func content<T>(as type: T.Type) -> T? { nodeContent as? T }

    override fileprivate func contentSizeThatFits(_ proposal: ProposedSize) -> Size {
        nodeContent.sizeThatFits(proposal, node: self)
    }

    override fileprivate func contentPlace(in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        nodeContent.place(node: self, in: rect, proposal: proposal, context: context, into: &list)
    }

    override fileprivate func contentFlexibility(along axis: Axis) -> LayoutPriorityClass {
        nodeContent.flexibility(along: axis, node: self)
    }

    override func contentHitTestOrder() -> [ViewNode]? {
        nodeContent.hitTestOrder(node: self)
    }

    override func contentPreference<K: PreferenceKey>(_ key: K.Type, below: K.Value?) -> K.Value? {
        nodeContent.preference(key, below: below)
    }
}

/// What a node can do, for the walks over the tree: one bit per ability its
/// content has, read when the node is made. A content is a value that does
/// not change, so neither do they.
struct NodeTraits: OptionSet, Sendable {
    let rawValue: UInt32

    static let transparent = NodeTraits(rawValue: 1 << 0)
    static let hitTarget = NodeTraits(rawValue: 1 << 1)
    static let dragSource = NodeTraits(rawValue: 1 << 2)
    static let dropTarget = NodeTraits(rawValue: 1 << 3)
    static let contextMenuSource = NodeTraits(rawValue: 1 << 4)
    static let hoverTarget = NodeTraits(rawValue: 1 << 5)
    static let textureInput = NodeTraits(rawValue: 1 << 6)
    static let focusTarget = NodeTraits(rawValue: 1 << 7)
    static let gestureAttachment = NodeTraits(rawValue: 1 << 8)
    /// `.allowsHitTesting(false)`: nothing here or below is hit.
    static let blocksHitTesting = NodeTraits(rawValue: 1 << 9)
    static let hitShape = NodeTraits(rawValue: 1 << 10)
    static let focusBinding = NodeTraits(rawValue: 1 << 11)
    static let keyPressHandler = NodeTraits(rawValue: 1 << 12)
    static let parked = NodeTraits(rawValue: 1 << 13)
    static let clipsChildren = NodeTraits(rawValue: 1 << 14)
    /// A layout that keeps a cache made from the subviews below it.
    static let layoutCacheOwner = NodeTraits(rawValue: 1 << 15)
    /// A layout with a say in the spacing it asks of its neighbours.
    static let spacingSource = NodeTraits(rawValue: 1 << 16)
    /// Keeps its new size while it moves rather than passing through the
    /// sizes in between — see `NodeContent.animatesSize`.
    static let keepsSizeWhileMoving = NodeTraits(rawValue: 1 << 17)
    /// A container's slot that a transition stands on (`TransitionSlotContent`).
    static let transitionSlot = NodeTraits(rawValue: 1 << 18)
    /// Placing it does more than draw from what it is placed with — see
    /// `NodeContent.placesPurely`. A subtree without one keeps what it
    /// drew (`PlacementCache.swift`).
    static let placesImpurely = NodeTraits(rawValue: 1 << 19)

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    @MainActor
    init<C: NodeContent>(of content: C) {
        var traits: NodeTraits = []
        if content.isTransparent { traits.insert(.transparent) }
        if content.hitTarget != nil { traits.insert(.hitTarget) }
        if content.dragSource != nil { traits.insert(.dragSource) }
        if content.dropTarget != nil { traits.insert(.dropTarget) }
        if content.contextMenuSource != nil { traits.insert(.contextMenuSource) }
        if content.hoverTarget != nil { traits.insert(.hoverTarget) }
        if content.textureInput != nil { traits.insert(.textureInput) }
        if content.focusTarget != nil { traits.insert(.focusTarget) }
        if content.gestureAttachment != nil { traits.insert(.gestureAttachment) }
        if !content.allowsHitTesting { traits.insert(.blocksHitTesting) }
        if content.hitShape != nil { traits.insert(.hitShape) }
        if content.focusBinding != nil { traits.insert(.focusBinding) }
        if content.keyPressHandler != nil { traits.insert(.keyPressHandler) }
        if content.isParked { traits.insert(.parked) }
        if content.clipsChildren { traits.insert(.clipsChildren) }
        if !content.animatesSize { traits.insert(.keepsSizeWhileMoving) }
        if C.self is any LayoutCacheOwner.Type { traits.insert(.layoutCacheOwner) }
        if C.self is any LayoutSpacingSource.Type { traits.insert(.spacingSource) }
        if C.self == TransitionSlotContent.self { traits.insert(.transitionSlot) }
        if !C.placesPurely { traits.insert(.placesImpurely) }
        self = traits
    }
}

/// What a node actually *is* — the layout and drawing behaviour behind it.
/// Every builtin view maps to one of these.
@MainActor
protocol NodeContent {

    /// Whether placing this draws from the rect, proposal and context it is
    /// placed with and its own values alone, placing its children into the
    /// list it was given — nothing kept anywhere else, nothing read that a
    /// rebuild or an animation asking for frames would not tell of. A subtree
    /// of such nodes keeps what it drew and draws it again
    /// (`PlacementCache.swift`). False unless a kind says so.
    static var placesPurely: Bool { get }


    /// True when the node contributes its children to the parent's layout
    /// rather than laying them out itself.
    var isTransparent: Bool { get }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size

    func place(
        node: ViewNode,
        in rect: Rect,
        proposal: ProposedSize,
        context: DrawContext,
        into list: inout DisplayList
    )

    /// A tap handler, if this node has one. Hit testing walks the placed tree
    /// back-to-front looking for these.
    var hitTarget: HitTarget? { get }

    /// What a drag starting on this node carries (`.draggable`), and what a
    /// drag ending on it may hand over (`.dropDestination`). Found by the
    /// same walk as `hitTarget`, but looked for separately — a drop target
    /// under the pointer is wanted even when a button sits on top of it.
    var dragSource: DragSource? { get }
    var dropTarget: DropTarget? { get }

    /// The menu a right click (or a long press) on this node opens.
    var contextMenuSource: ContextMenuSource? { get }

    /// Told when the pointer moves over or off this node (`.onHover`).
    var hoverTarget: HoverTarget? { get }

    /// Hover moves for a `TextureView`, which passes them on to its source.
    var textureInput: TextureInputTarget? { get }

    /// Takes the keys once pressed — a `TextField`, a `TextureView`.
    var focusTarget: FocusTarget? { get }

    /// A gesture attached with `.gesture` and its kin, run by the host's
    /// `GestureArena` for a press inside this node.
    var gestureAttachment: GestureAttachment? { get }

    /// False for `.allowsHitTesting(false)`: neither this node nor anything
    /// under it is found by any hit test.
    var allowsHitTesting: Bool { get }

    /// The shape a press must land inside to reach this node and what it
    /// wraps (`.contentShape`), in place of its frame.
    var hitShape: HitShape? { get }

    /// A `.focused` binding, kept in step with where the keys are.
    var focusBinding: FocusBindingRecord? { get }

    /// An `.onKeyPress` action, offered the keys while this node or one
    /// inside it has them.
    var keyPressHandler: KeyPressHandler? { get }

    /// The transition this node gives the view it wraps (`.transition`).
    var transitionTrait: AnyTransition? { get }

    /// Whether this node's frame passes through the sizes in between while
    /// it animates — true for most; false for text, which would reflow at
    /// each and so keeps its new size while it moves.
    var animatesSize: Bool { get }

    /// True for a subtree kept in the tree but off screen (`._parked`). Its
    /// nodes still carry the frames from when they were last placed, and hit
    /// testing must not trust them.
    var isParked: Bool { get }

    /// True when this node clips its children to its own frame — a
    /// `ScrollView`, `.clipped()`, `.cornerRadius()`. What is not drawn must
    /// not be hit either: a row scrolled up under a navigation bar would
    /// otherwise take the tap meant for the bar.
    var clipsChildren: Bool { get }

    /// How eagerly this node consumes leftover space along `axis` — a stack
    /// sizes its least flexible children first so a greedy sibling can't
    /// squeeze a `Text`. Takes the node so a wrapper can answer for what it
    /// wraps and a stack for its children.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass

    /// The children in paint order, when that isn't `children` — a lazy
    /// container draws its pinned headers last, over the rows, and they
    /// must be hit first too. `nil` for the usual order.
    func hitTestOrder(node: ViewNode) -> [ViewNode]?

    /// This node's value for preference `key`, given the value its children
    /// reduced to (`nil` when none of them set one); `nil` passes "unset" on
    /// up. A writer replaces its subtree's value, a transform edits it;
    /// every other node passes `below` through.
    func preference<K: PreferenceKey>(_ key: K.Type, below: K.Value?) -> K.Value?
}

extension NodeContent {
    static var placesPurely: Bool { false }
    var isTransparent: Bool { false }
    var hitTarget: HitTarget? { nil }
    var dragSource: DragSource? { nil }
    var dropTarget: DropTarget? { nil }
    var contextMenuSource: ContextMenuSource? { nil }
    var hoverTarget: HoverTarget? { nil }
    var textureInput: TextureInputTarget? { nil }
    var focusTarget: FocusTarget? { nil }
    var gestureAttachment: GestureAttachment? { nil }
    var allowsHitTesting: Bool { true }
    var hitShape: HitShape? { nil }
    var focusBinding: FocusBindingRecord? { nil }
    var keyPressHandler: KeyPressHandler? { nil }
    var transitionTrait: AnyTransition? { nil }
    var animatesSize: Bool { true }
    var isParked: Bool { false }
    var clipsChildren: Bool { false }
    func hitTestOrder(node: ViewNode) -> [ViewNode]? { nil }
    func preference<K: PreferenceKey>(_ key: K.Type, below: K.Value?) -> K.Value? { below }

    /// Most nodes are as flexible as whatever they wrap — a padded, tinted,
    /// tappable fixed frame is still fixed. Only a `Spacer` (fully flexible),
    /// a `.frame` (whatever it constrains to) and the stacks (their children)
    /// say otherwise; a leaf with nothing inside is content-sized.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        node.singleChild?.flexibility(along: axis) ?? .content
    }

    /// Default sizing: pass the proposal through to the wrapped child, or take
    /// the whole proposal when there is nothing inside.
    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        guard let child = node.singleChild else {
            return proposal.replacingUnspecifiedDimensions()
        }
        return child.sizeThatFits(proposal)
    }

    /// Default placement: hand the whole rect, and the proposal that made it,
    /// to the wrapped child.
    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}

/// A node that draws nothing and lays nothing out — it exists to hold
/// children. `EmptyView`, `TupleView`, `Group`, `ForEach` and the builder's
/// conditional wrappers all become one.
struct GroupContent: NodeContent {
    var isTransparent: Bool { true }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        // Only reached when a group is the *root* or the sole child of a
        // modifier — otherwise the parent flattened it away. Behave like a
        // ZStack so multiple children still get a sensible box.
        let children = node.layoutChildren
        guard !children.isEmpty else { return .zero }
        var result = Size.zero
        for child in children {
            let size = child.sizeThatFits(proposal)
            result.width = max(result.width, size.width)
            result.height = max(result.height, size.height)
        }
        return result
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        for child in node.layoutChildren {
            child.place(in: rect, proposal: proposal, context: context, into: &list)
        }
    }
}

/// Reduce any view to a layout node, evaluating `body` until a builtin is
/// reached. This is the single seam between the declarative surface and
/// everything below it.
///
/// Before building, ask whether the subtree standing at this position from
/// the last pass will do. It will if the view is the same view — same type
/// and call site — with equivalent inputs, built under an equivalent
/// environment and stack axis, and nothing at or beneath it was dirtied by a
/// state write. Then the old node is grafted in and `body` is never run.
/// Every one of those conditions is necessary: the inputs are what `body`
/// reads, the environment and axis are what the builtins read, and a dirty
/// descendant is a view whose own reads changed under it.
@MainActor
func buildNode<V: View>(_ view: V, _ context: inout BuildContext) -> ViewNode {
    let path = context.path
    let identity = ViewIdentity(type: ObjectIdentifier(V.self), viewID: view._viewID)
    // Whether the view standing here already drew into a node of its own;
    // a fresh build of the same view keeps it (see `RenderBoundaryContent`).
    var wasBoundary = false
    // The node the view standing here last produced, when it is the same
    // view — the one a fresh build takes its motion over from.
    var predecessor: ViewNode?
    // Inside a lazy container: the window and starting unit this build is
    // under, which a standing view must have been built under too.
    let lazyCursor = context.lazyCursor
    let lazyKey = lazyCursor?.key

    if let candidate = context.candidate {
        // `identity` first: it carries the type, which `isEquivalent` relies on.
        let reusable = candidate.identity == identity
            && candidate.stackAxis == context.stackAxis
            && candidate.lazyKey == lazyKey
            && !context.isDirtyHereOrBelow
            && candidate.readsAgree(with: context.environment)
            && candidate.isEquivalent(to: view)
        if reusable {
            let node = candidate.standingNode
            lazyCursor?.position += candidate.lazyUnits
            // What the kept subtree read, the view around it has read too.
            EnvironmentReads.shared.add(candidate.environmentReads)
            context.reuse(candidate)
            if PerfTrace.isEnabled { PerfTrace.nodesReused += 1 }
            PerfTrace.trace("reuse \(path) \(V.self)")
            return node
        }
        // Which check failed, worked out again only for the verbose trace.
        PerfTrace.trace({
            let reason = candidate.identity != identity ? "identity"
                : candidate.stackAxis != context.stackAxis ? "stack axis"
                : candidate.lazyKey != lazyKey ? "lazy window"
                : context.isDirtyHereOrBelow ? "dirty"
                : !candidate.readsAgree(with: context.environment) ? "environment"
                : "inputs"
            return "build \(path) \(V.self) — \(reason)"
        }())

        // A fresh build replaces what stood here. Its reader registrations
        // are stale from this moment — the reads are about to happen again —
        // and its state is only carried over if this is still the same view.
        let replaced = context.records.replace(candidate)
        let reader = context.position.handle
        for storage in replaced.reads {
            storage.readers.remove(reader)
        }
        if replaced.identity != identity {
            var left = RebuildRecords.Departed()
            context.position.release(into: &left)
            context.effects.forget(paths: [path], disappearing: left.disappearing)
            context.animations.forget(exits: left.exits)
        } else {
            wasBoundary = replaced.isBoundary
            predecessor = replaced.node
        }
    } else {
        PerfTrace.trace("build \(path) \(V.self) — new")
    }

    // Every environment value read from here until the view is built —
    // by its `@Environment`s, bound next, by the builtin it is or the body
    // it has, by everything built under it — is one it depends on.
    EnvironmentReads.shared.begin()

    // Wire up @State / @Environment before anything reads `body` — on this
    // copy, which is the one built and recorded.
    var view = view
    context.bindDynamicProperties(of: &view)

    // Publish this view's identity for the duration of its own evaluation, so
    // any `@State` read below is attributed to it — that attribution is what
    // lets a later write rebuild only this subtree.
    DependencyTracker.shared.push(context.position.handle)

    var node: ViewNode
    var isBoundary = false
    if let builtin = builtinMaker(for: view) {
        context.viewIdentity = identity
        context.isReplacingStandingView = predecessor != nil
        // Only the views that dissolve into a lazy container's layout build
        // under its cursor; any other builtin is one of its items, and
        // builds what it holds eagerly.
        let passesCursor = builtin.passesCursor
        if !passesCursor { context.lazyCursor = nil }
        node = withUnsafePointer(to: view) { builtin.makeNode(UnsafeRawPointer($0), &context) }
        context.lazyCursor = lazyCursor
        if !passesCursor, let lazyCursor {
            lazyCursor.position += node.lazyLayoutCount
        }
    } else {
        // The body's `@Observable` reads belong to this view. Only the body
        // itself is inside the scope — the child it returns is built after,
        // in a scope of its own — so a change rebuilds from here, not from
        // every ancestor that happened to be mid-build.
        // An `Animatable` view mid-change shows its in-between value.
        let shown = context.showing(view)
        let body = trackingObservation(at: path) { shown.body }
        node = context.child(0) { sub in buildNode(body, &sub) }
        // A user view that a change can originate at draws into a node of
        // its own: it read `@State`, or this very build is the rebuild its
        // own reads asked for. Not one whose body dissolves into the
        // parent's layout (a `Group`, a `ForEach`): a node is one laid-out
        // box.
        isBoundary = (wasBoundary || context.isDirtyHere || DependencyTracker.shared.currentViewHasReads)
            && !node.isTransparent
        if isBoundary {
            let body = node
            node = ContentNode(
                content: RenderBoundaryContent(key: RenderNodeKey(slot: context.position.renderSlot, identity: identity)),
                children: [body]
            )
            node.transitionTrait = body.transitionTrait
            node.gridCellTraits = body.gridCellTraits
            node.layoutValues = body.layoutValues
        }
    }
    if node.ownerPath == nil { node.ownerPath = path }
    if let predecessor, predecessor !== node, node.ownerPath == path {
        node.inheritMotion(from: predecessor)
    }
    let reads = DependencyTracker.shared.pop()
    let environmentReads = EnvironmentReads.shared.end()

    // Remember how to rebuild exactly this view in exactly this position, and
    // how to recognise it next time. The record holds the concrete view
    // value: a scoped rebuild re-runs it without walking down from the root,
    // and a parent that re-runs compares its new child against it.
    context.record(
        RebuildRecords.Entry(
            identity: identity,
            environment: context.environment,
            environmentReads: environmentReads,
            stackAxis: context.stackAxis,
            view: RecordedViewOf(view),
            node: node,
            reads: reads,
            isBoundary: isBoundary,
            lazyKey: lazyKey,
            lazyUnits: lazyKey.map { lazyCursor!.position - $0.start } ?? 0
        )
    )
    return node
}

/// How `buildNode` makes the node of a builtin view. Whether a view type is
/// a `BuiltinView` is a conformance lookup, and asking it with `as?` also
/// copies the view into an existential box — on every build of every view;
/// so it is asked once per type, and the answer kept.
private struct BuiltinMaker {
    /// The builtin's `makeNode`, given a pointer to a view of its type.
    let makeNode: @MainActor (UnsafeRawPointer, inout BuildContext) -> ViewNode
    /// A `LazyPassThrough`: builds under a lazy container's cursor.
    let passesCursor: Bool
}

/// By view type; `nil` for a view that builds through its `body`.
@MainActor
private var builtinMakers: [ObjectIdentifier: BuiltinMaker?] = [:]

@MainActor
private func builtinMaker<V: View>(for view: V) -> BuiltinMaker? {
    let id = ObjectIdentifier(V.self)
    if let known = builtinMakers[id] { return known }
    // A view is a value of exactly its static type, so what one says goes
    // for the type.
    precondition(type(of: view) == V.self, "a view type is a struct")
    var maker: BuiltinMaker?
    if let builtin = view as? BuiltinView { maker = openBuiltinMaker(builtin) }
    builtinMakers[id] = .some(maker)
    return maker
}

@MainActor
private func openBuiltinMaker<B: BuiltinView>(_ builtin: B) -> BuiltinMaker {
    BuiltinMaker(
        makeNode: { view, context in view.assumingMemoryBound(to: B.self).pointee.makeNode(&context) },
        passesCursor: builtin is LazyPassThrough
    )
}
