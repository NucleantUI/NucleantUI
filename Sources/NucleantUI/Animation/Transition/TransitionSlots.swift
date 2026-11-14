//
//  TransitionSlots.swift
//  NucleantUI
//
//  The containers' side of transitions. An `if`, a `switch`, a `ForEach`
//  and a builder's `for` insert and remove their children; a child that
//  arrives or leaves gets its transition's body (Transition.swift) built
//  around it, and moved from phase to phase.
//
//  The child is built where it always is — its path, its state and its
//  node are any child's — and the body beside it, at
//  `C + [TransitionSlot.bodies, i]` for child slot `i` of the container at
//  `C`. The container then holds, for that slot, a node of its own over the
//  body (`TransitionSlotContent`), and the body's placeholder stands for a
//  node over the child (`TransitionContentContent`): a rebuilt child is
//  swapped in under it, and a leaving one is frozen there.
//
//  Arriving: the body built in `willAppear` with no animation, then
//  straight away in `identity` under the change's, in the same pass —
//  every value the body's modifiers keep starts where `willAppear` puts it
//  and animates to where `identity` does. Leaving: the body built in
//  `didDisappear` under the animation; the slot stays among the container's
//  children, drawn where it last stood but out of layout and of hit
//  testing, until every animation that change started has run out. Back
//  while leaving: `identity` again, from wherever the exit had got to.
//
//  A transition runs only in a container that stood before — one built
//  from scratch has nothing arriving into it — and only when the change
//  animates, or the transition brings an animation of its own.
//
//  The framework's own transitions change nothing in `identity`, so their
//  body stands on a child only while it arrives or leaves: a list of a
//  thousand rows is a thousand rows, not a thousand wrappers faded in
//  full. Any other transition stays on its view while it is shown — its
//  identity phase is part of how the view looks.
//
//  Nor do they build a body at all. A framework transition says what its
//  body would draw in each phase — an opacity, an offset, a move, a scale
//  (TransitionEffect.swift) — and its slot's node draws that around the
//  node over the child itself, the numbers animated from phase to phase:
//  the same picture, with nothing built for an arrival or an exit. Only a
//  transition that cannot say — one written outside the framework, or one
//  carrying an animation of its own — has its body built, as above.
//

/// One child slot of a structural container while a transition's body
/// stands on it.
@MainActor
final class TransitionSlot {

    /// The path component a container's transition bodies are built under:
    /// child slot `i` of the container at `C` has its body at
    /// `C + [bodies, i]`. No container builds a child in this slot: a
    /// `ForEach` numbers its rows from 0 (`RowSlots`).
    static let bodies = Int.min + 1

    /// The child's slot in its container.
    let index: Int

    /// Over the child, under the body: what the body's placeholder stands
    /// for. A rebuilt child is swapped in here.
    let content: ViewNode

    /// What the container holds for the slot, over the body. Kept from one
    /// build of the container to the next: the body under it is rebuilt on
    /// its own — a scoped rebuild splices into it — and a leaving slot
    /// stays marked as one, on it.
    let node: ViewNode

    /// The transition the body is built from.
    private(set) var transition: AnyTransition

    /// What the arrival started. The body of a transition that changes
    /// nothing in `identity` is taken off once every one has run out.
    var arrival: [AnimationRun] = []

    /// For a built-in transition that says what it draws: the effects the
    /// slot's node draws the child with, in place of a body. Emptied when
    /// the slot takes a transition that has to build its body.
    let effects: TransitionEffects

    /// A slot whose transition's body is built, standing on `content`.
    init(index: Int, content: ViewNode, body: ViewNode, transition: AnyTransition) {
        self.index = index
        self.content = content
        effects = TransitionEffects([])
        self.node = ContentNode(content: TransitionSlotContent(content: content, effects: effects), children: [body])
        self.transition = transition
    }

    /// A slot that draws its transition's `effects` itself: no body, the
    /// node over the child is the slot's only child.
    init(index: Int, content: ViewNode, effects: [TransitionEffect], transition: AnyTransition) {
        self.index = index
        self.content = content
        self.effects = TransitionEffects(effects)
        self.node = ContentNode(content: TransitionSlotContent(content: content, effects: self.effects), children: [content])
        self.transition = transition
    }

    /// Whether the slot draws effects rather than a body.
    var drawsEffects: Bool { node.children.first === content }

    /// The child left and its exit is playing.
    var isLeaving: Bool { node.isLeaving }

    /// The exit has played out: the slot goes with the container's next
    /// build.
    var hasLeft: Bool { node.removal?.isFinished ?? false }

    /// Where the slot stood among the container's children when it left.
    var exitPosition: Int { node.removal?.position ?? 0 }

    /// Stand on `child` — the same node, or a rebuilt one in its place.
    func show(_ child: ViewNode) {
        guard content.children.first !== child else { return }
        content.replaceChild(at: 0, with: child)
        // The body and the slot measured the child that was there.
        content.invalidateMeasurementsUpwards()
    }

    func use(_ transition: AnyTransition) {
        self.transition = transition
    }

    /// Put `body`, just built or reused, under the slot's node.
    func setBody(_ body: ViewNode) {
        guard node.children.first !== body else { return }
        node.replaceChild(at: 0, with: body)
        node.invalidateMeasurementsUpwards()
    }

    /// The slot's node stands for `child` in its container: what a
    /// container reads off a child's node, it reads off this one.
    func carryTraits(of child: ViewNode) {
        node.transitionTrait = child.transitionTrait
        node.gridCellTraits = child.gridCellTraits
        node.layoutValues = child.layoutValues
        node.lazyTag = child.lazyTag
        node.sectionTag = child.sectionTag
    }
}

/// A child slot on its way out: where it stood, and what its exit is
/// waiting on.
struct NodeRemoval {
    /// The container it is leaving, rebuilt once the exit is over. Held
    /// weakly: the container's position holds the slot, and so this.
    weak var container: ViewPosition?
    /// Where, how and under what transform the slot last stood.
    let frame: Rect
    let proposal: ProposedSize
    let transform: Transform
    /// Its place among the container's children then.
    let position: Int
    /// The frame the exit began in: the one whose placement still starts
    /// animations for it.
    let startFrame: Int
    /// Every animation the exit started. It is over when they all are.
    var runs: [AnimationRun]
    /// The frame it was last drawn in, so it is drawn once per pass.
    var drawnInFrame = 0
    var isFinished = false
}

// MARK: - The nodes

/// What a container holds for a child slot with a transition standing on
/// it: lays out, draws and is hit as the body under it.
struct TransitionSlotContent: NodeContent {
    /// The node over the child.
    let content: ViewNode
    /// What a built-in transition draws, when the slot stands without a
    /// body: applied around the child here, as its modifiers would be.
    let effects: TransitionEffects

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        node.singleChild?.place(in: rect, proposal: proposal, context: effects.apply(to: context, in: rect), into: &list)
    }
}

/// The node between a transition's body and the child it stands on: lays
/// out, draws and is hit as the child. While the slot leaves, the child is
/// frozen as it stood — no motion starts or carries on in it, and nothing
/// in it builds: its views are gone, only their nodes are drawn.
struct TransitionContentContent: NodeContent {
    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard context.frozenTransitionContent == ObjectIdentifier(node) else {
            node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
            return
        }
        var inner = context
        inner.freezesMotion = true
        inner.frozenTransitionContent = nil
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

extension ViewNode {
    /// The child a transition stands on, for a container's slot node; the
    /// node itself otherwise. What a container that looks at what kind of
    /// children it has — a `Grid` finding its rows — looks at.
    var underTransition: ViewNode {
        guard traits.contains(.transitionSlot),
              let slot = content(as: TransitionSlotContent.self), let child = slot.content.singleChild else {
            return self
        }
        return child.underTransition
    }
}

// MARK: - Building

extension BuildContext {

    /// The table the `ForEach` being built gives its rows their slots from,
    /// by id — on its position.
    func rowSlots<ID: Hashable>(for _: ID.Type) -> RowSlots<ID> {
        position.rowSlots(ID.self)
    }

    /// The children of an `if`, a `switch`, a `ForEach` or a `for`, with
    /// their transitions: `built` is every child just built, in order, by
    /// slot, with whether it is new here. Returns the container's children
    /// — each built child, or its slot's node where a transition stands on
    /// it — with the children still leaving back where they stood.
    func transitionChildren(_ built: [(index: Int, node: ViewNode, isNew: Bool)]) -> [ViewNode] {
        let stood = isReplacingStandingView && animations.runsTransitions
        let container = position
        let previous = container.transitionSlots
        var slots: [Int: TransitionSlot] = [:]
        var children: [ViewNode] = []
        children.reserveCapacity(built.count)

        for child in built {
            children.append(slotNode(for: child, stood: stood, standing: previous[child.index], into: &slots))
        }
        // What stood here and was not built again has been removed.
        if stood {
            for (index, node) in leftoverChildren {
                beginExit(index: index, child: node, standing: previous[index], built: built, into: &slots)
            }
        }
        // Exits begun before, still playing. Their bodies are built again
        // with the container's, so they stand as long as the exit does.
        for (index, slot) in previous where slot.isLeaving && slots[index] == nil && !slot.hasLeft {
            show(slot, in: .didDisappear, animation: transaction.animation)
            slots[index] = slot
        }
        let leaving = slots.values.filter(\.isLeaving)
        if !leaving.isEmpty {
            for slot in leaving.sorted(by: { $0.exitPosition < $1.exitPosition }) {
                children.insert(slot.node, at: min(slot.exitPosition, children.count))
            }
        }
        container.transitionSlots = slots
        return children
    }

    /// What the container holds for `child`: the child, or its slot's node
    /// while a transition stands on it.
    private func slotNode(
        for child: (index: Int, node: ViewNode, isNew: Bool),
        stood: Bool,
        standing: TransitionSlot?,
        into slots: inout [Int: TransitionSlot]
    ) -> ViewNode {
        let node = child.node
        // A group dissolves into the container's layout: there is no one
        // view to move.
        guard !node.isTransparent else { return node }
        let transition = node.transitionTrait ?? .opacity
        let box = transition.box
        guard !box.isIdentity else { return node }

        if let slot = standing, slot.isLeaving, !slot.hasLeft {
            // Back while leaving: to `identity`, from wherever the exit
            // had got to.
            slot.node.removal = nil
            animations.exitEnded(slot.node)
            slot.show(node)
            slot.use(transition)
            slot.arrival = collectingRuns { show(slot, in: .identity, animation: transaction.animation) }
            return keep(slot, standingFor: node, in: &slots)
        }
        if child.isNew, stood, transaction.animation != nil || box.animatesArrival {
            // Arriving: from `willAppear`, built without animation, to
            // `identity` under the change's.
            let slot = makeSlot(child.index, standingOn: node, transition: transition, phase: .willAppear)
            slot.arrival = collectingRuns { show(slot, in: .identity, animation: transaction.animation) }
            return keep(slot, standingFor: node, in: &slots)
        }
        if let slot = standing, !slot.isLeaving {
            if box.leavesViewUnchangedAtIdentity, slot.arrival.allSatisfy({ $0.isDone(at: animations.now) }) {
                // Arrived, and its body changes nothing any more.
                return node
            }
            slot.show(node)
            slot.use(transition)
            show(slot, in: .identity, animation: transaction.animation)
            return keep(slot, standingFor: node, in: &slots)
        }
        if !box.leavesViewUnchangedAtIdentity {
            // On the view, in `identity`, for as long as it is shown.
            let slot = makeSlot(child.index, standingOn: node, transition: transition, phase: .identity)
            return keep(slot, standingFor: node, in: &slots)
        }
        return node
    }

    /// Start the exit of `child`, removed from slot `index`: its body in
    /// `didDisappear`, under the animation — or nothing, the child simply
    /// gone, when there is nothing to animate it with.
    private func beginExit(
        index: Int,
        child: ViewNode,
        standing: TransitionSlot?,
        built: [(index: Int, node: ViewNode, isNew: Bool)],
        into slots: inout [Int: TransitionSlot]
    ) {
        guard !child.isTransparent else { return }
        let transition = child.transitionTrait ?? .opacity
        let box = transition.box
        guard !box.isIdentity, transaction.animation != nil || box.animatesRemoval else { return }
        // Where the view last stood: its slot's node if a body stood on
        // it, else the child itself. Never placed — nothing to see leave.
        let shown = standing?.node ?? child
        guard shown.frame.width > 0 || shown.frame.height > 0 else { return }
        // Read before a slot is made for it: that puts the child under a
        // node of its own, and where it stood is where its parent was.
        let position = position(of: shown, inSlot: index, among: built)

        let slot: TransitionSlot
        if let standing {
            slot = standing
            slot.show(child)
            slot.use(transition)
        } else {
            // The view as it stood, in `identity`, for the exit to start
            // from.
            slot = makeSlot(index, standingOn: child, transition: transition, phase: .identity)
        }
        let runs = collectingRuns { show(slot, in: .didDisappear, animation: transaction.animation) }
        slot.node.removal = NodeRemoval(
            container: self.position,
            frame: shown.frame,
            proposal: shown.proposal,
            transform: shown.transform,
            position: position,
            startFrame: animations.frame,
            runs: runs
        )
        animations.exitBegan(slot.node)
        slot.carryTraits(of: child)
        slots[index] = slot
    }

    /// Where `node`, removed from slot `index`, stood among this
    /// container's children: counting the children that were there with
    /// it — not ones already leaving then — so it goes back between the
    /// same two. A container whose node was its one child (an `if` with
    /// nothing leaving beside it) held nothing to count; there its
    /// children are in slot order, as an `if`'s branches are.
    private func position(
        of node: ViewNode,
        inSlot index: Int,
        among built: [(index: Int, node: ViewNode, isNew: Bool)]
    ) -> Int {
        if let parent = node.parent, parent.owner === self.position.handle,
           parent.children.indices.contains(node.indexInParent),
           parent.children[node.indexInParent] === node {
            var position = 0
            for sibling in parent.children[..<node.indexInParent] where !sibling.isLeaving {
                position += 1
            }
            return position
        }
        return built.reduce(0) { $0 + ($1.index < index ? 1 : 0) }
    }

    /// A slot standing on `child`, its body built in `phase` without
    /// animation.
    private func makeSlot(
        _ index: Int,
        standingOn child: ViewNode,
        transition: AnyTransition,
        phase: TransitionPhase
    ) -> TransitionSlot {
        let content = ContentNode(content: TransitionContentContent(), children: [child])
        if let effects = transition.box.effects(in: phase) {
            return TransitionSlot(index: index, content: content, effects: effects, transition: transition)
        }
        let body = buildBody(index, transition: transition, standingOn: content, phase: phase, animation: nil)
        return TransitionSlot(index: index, content: content, body: body, transition: transition)
    }

    /// Show `slot` in `phase`, under `animation`: its effects moved there,
    /// or its body built again for it. A slot that drew effects and now
    /// has a transition that cannot builds its body from here on.
    private func show(_ slot: TransitionSlot, in phase: TransitionPhase, animation: Animation?) {
        if slot.drawsEffects, let effects = slot.transition.box.effects(in: phase) {
            slot.effects.update(to: effects, animation: animation, in: animations)
            return
        }
        slot.effects.update(to: nil, animation: nil, in: animations)
        slot.setBody(buildBody(slot.index, transition: slot.transition, standingOn: slot.content, phase: phase, animation: animation))
    }

    private func buildBody(
        _ index: Int,
        transition: AnyTransition,
        standingOn content: ViewNode,
        phase: TransitionPhase,
        animation: Animation?
    ) -> ViewNode {
        var context = self
        context.move(to: path + [TransitionSlot.bodies, index])
        // Not one of a lazy container's items: the child it stands on was
        // counted as one.
        context.lazyCursor = nil
        context.transaction.animation = animation
        return transition.box.makeBody(phase: phase, content: PlaceholderNodeContent(content), context: &context)
    }

    private func keep(_ slot: TransitionSlot, standingFor child: ViewNode, in slots: inout [Int: TransitionSlot]) -> ViewNode {
        slot.carryTraits(of: child)
        slots[slot.index] = slot
        return slot.node
    }

    /// The animations `body` starts.
    private func collectingRuns(_ body: () -> Void) -> [AnimationRun] {
        animations.beginCollectingRuns()
        body()
        return animations.endCollectingRuns()
    }
}

// MARK: - Placing the slots that leave

extension ViewNode {

    /// Draw the leaving slots that stand just before this node among its
    /// parent's children — before this node is drawn, so a view leaving
    /// keeps its place in the order things are drawn: under what came
    /// after it, over what came before. The rest are drawn after the
    /// parent's own children (`placeLeavingChildren`).
    func placeLeavingBefore(context: DrawContext, store: AnimationStore, into list: inout DisplayList) {
        guard let parent, indexInParent > 0 else { return }
        let siblings = parent.children
        guard indexInParent <= siblings.count, siblings[indexInParent - 1].isLeaving else { return }
        var first = indexInParent - 1
        while first > 0, siblings[first - 1].isLeaving { first -= 1 }
        for index in first..<indexInParent {
            siblings[index].placeLeaving(context: context, store: store, into: &list)
        }
    }

    /// Draw the slots still leaving that nothing drew yet this pass —
    /// directly held, or held by a group dissolved into this node's layout.
    func placeLeavingChildren(context: DrawContext, store: AnimationStore, into list: inout DisplayList) {
        for child in children {
            if child.isLeaving {
                child.placeLeaving(context: context, store: store, into: &list)
            } else if child.isTransparent {
                child.placeLeavingChildren(context: context, store: store, into: &list)
            }
        }
    }

    /// Draw this leaving slot where it last stood, its body moving and the
    /// child under it frozen — and end the exit once everything it started
    /// has run out.
    func placeLeaving(context: DrawContext, store: AnimationStore, into list: inout DisplayList) {
        guard var removal, !removal.isFinished, removal.drawnInFrame != store.frame else { return }
        removal.drawnInFrame = store.frame
        self.removal = removal

        var inner = context
        inner.transform = removal.transform
        if let slot = content as? TransitionSlotContent {
            inner.frozenTransitionContent = ObjectIdentifier(slot.content)
        }
        // Placed for the first time in the pass that began the exit: what
        // its body starts moving here is part of the exit too.
        let isFirst = removal.startFrame == store.frame
        if isFirst { store.beginCollectingRuns() }
        place(in: removal.frame, proposal: removal.proposal, context: inner, into: &list)
        if isFirst { removal.runs += store.endCollectingRuns() }

        if removal.runs.allSatisfy({ $0.isDone(at: store.now) }) {
            removal.isFinished = true
            store.exitFinished(self, container: removal.container)
        } else {
            store.requestFrame()
        }
        self.removal = removal
    }
}
