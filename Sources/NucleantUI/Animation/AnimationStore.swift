//
//  AnimationStore.swift
//  NucleantUI
//
//  One view tree's animation clock and everything that animates against
//  it. The host stamps the time once per frame, so every value placed in
//  one pass is sampled at the same instant; anything still moving when the
//  pass ends asks for another frame, and the host lays out again — nothing
//  is rebuilt for it.
//
//  Four kinds of motion, all started by a pass that *built* something
//  (a commit pass) and only followed by the passes after:
//
//  * values — a modifier's own parameters (opacity, scale, rotation, a
//    fill color), kept on the view's position (`ViewPosition`) so a
//    rebuild picks up where the last build's value was;
//  * animatable data — an `Animatable` view's, shape's or modifier's own
//    `animatableData` (Animatable.swift), kept there too: a shape redraws
//    at each value, a view is rebuilt at each, its path dirtied frame by
//    frame until done;
//  * geometry — a node placed somewhere other than where it last stood
//    (`ViewNode.animate`, in NodeMotion.swift);
//  * transitions — a view inserted into, or removed from, an `if`, a
//    `switch`, a `ForEach` or a `for`: the framework's transitions drawn
//    around it as effects whose numbers animate, any other transition's
//    body built around it and moved from phase to phase, the body's own
//    values doing the animating (Transition/TransitionSlots.swift). A
//    removed one stays drawn, out of layout, until everything its exit
//    started is over.
//

import Foundation
import Dispatch

@MainActor
final class AnimationStore {

    /// The store of the host whose frame is in progress. Set for the
    /// whole of `ViewHost.update`, the way `ShaderHost.current` is for
    /// placement.
    static var current: AnimationStore?

    /// Seconds on a monotonic clock, fixed for the frame.
    private(set) var now: Double = 0

    /// Bumped every frame, so a leaving view reached twice in one pass is drawn
    /// once and a scoped change can tell "this frame" from "some frame".
    private(set) var frame = 0

    /// Whether this frame built anything. Only such a frame starts
    /// animations; the frames after only follow them.
    private(set) var isCommitPass = false

    /// The transaction the writes served this frame were made in.
    private(set) var transaction = Transaction()

    /// Something placed this pass is still moving.
    private var movedThisPass = false

    /// Whether the next frame should lay out again even if nothing
    /// changed — decided as the previous one ended.
    private(set) var wantsFrame = false

    // MARK: - Frames

    func beginFrame() {
        now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        frame += 1
    }

    /// A pass that builds under `transaction`, or only lays out again.
    func beginPass(transaction: Transaction?, isCommit: Bool) {
        self.transaction = transaction ?? Transaction()
        isCommitPass = isCommit
        movedThisPass = false
        pending += self.transaction.completions
    }

    /// Called by whatever is still between two values as it is placed.
    func requestFrame() {
        movedThisPass = true
        // Whatever asked is on its way: what it is part of draws something
        // else next frame, and is not kept (`PlacementCache.swift`).
        PlacementRecorder.shared.noteDisturbance()
    }

    /// An animation began in this pass: whichever `withAnimation`
    /// completions ride on the pass wait for it, and so does whatever is
    /// collecting the runs started meanwhile.
    func noteStarted(_ run: AnimationRun) {
        for completion in transaction.completions {
            completion.runs.append(run)
        }
        for index in collectors.indices {
            collectors[index].append(run)
        }
    }

    /// Runs started since each open `beginCollectingRuns`, innermost last.
    private var collectors: [[AnimationRun]] = []

    /// Start collecting the animations started from here on — what a
    /// transition's change of phase started, which its exit waits on.
    func beginCollectingRuns() {
        collectors.append([])
    }

    /// The animations started since the matching `beginCollectingRuns`.
    func endCollectingRuns() -> [AnimationRun] {
        collectors.removeLast()
    }

    func endPass() {
        for completion in transaction.completions {
            completion.isScheduled = true
        }
        // A repeat that never ends never completes — unless it was told
        // when to count as logically complete, and that is what the
        // completion waits for; waiting on it would only keep the clock
        // running.
        pending.removeAll { completion in
            completion.isScheduled && completion.runs.contains { run in
                run.isEndless && (completion.criteria == .removed || run.animation.logicalCompletionTime == nil)
            }
        }
        transaction = Transaction()
        isCommitPass = false
        wantsFrame = movedThisPass || !pending.isEmpty
    }

    // MARK: - Completions

    /// `withAnimation(completion:)` callbacks whose frame has run.
    private var pending: [AnimationCompletion] = []

    /// The callbacks now due — their animations over, or a body that
    /// changed nothing.
    func takeDueCompletions() -> [AnimationCompletion] {
        var due = AnimationCompletion.unclaimed
        AnimationCompletion.unclaimed.removeAll()
        pending.removeAll { completion in
            guard completion.isScheduled, completion.isDue(at: now) else { return false }
            due.append(completion)
            return true
        }
        return due
    }

    // MARK: - Values

    /// Which of a node's parameters a value is — one node, one modifier,
    /// so the kinds never collide at a position.
    enum Slot: Hashable {
        case opacity, rotation, scale, offset, move, fill, stroke, textColor
    }

    /// The value for `slot` of the view at `position`, of a type of its own
    /// — an opacity, an offset — moved to `target`: at once, or over
    /// `animation` from wherever it is now.
    func state<Data: VectorArithmetic>(
        at position: ViewPosition,
        slot: Slot,
        target: Data,
        animation: Animation?
    ) -> AnimatableDataState<Data> {
        let type = ObjectIdentifier(AnimatableDataState<Data>.self)
        for index in position.animatedStates.indices where position.animatedStates[index].slot == slot {
            let standing = position.animatedStates[index].state
            if ObjectIdentifier(Swift.type(of: standing)) == type {
                let existing = unsafeDowncast(standing, to: AnimatableDataState<Data>.self)
                existing.update(to: target, animation: animation, in: self)
                return existing
            }
            // A value of another type in the slot: starts where it is.
            let created = AnimatableDataState(target)
            position.animatedStates[index].state = created
            return created
        }
        let created = AnimatableDataState(target)
        position.animatedStates.append((slot, created))
        return created
    }

    /// The value for `slot` of the view at `position`, as numbers, moved to
    /// `target` — at once, or over `animation` from wherever it is now.
    func value(at position: ViewPosition, slot: Slot, target: [Double], animation: Animation?) -> AnimatedVector {
        for entry in position.animatedVectors where entry.slot == slot {
            entry.value.update(to: target, animation: animation, in: self)
            return entry.value
        }
        let created = AnimatedVector(target)
        position.animatedVectors.append((slot, created))
        return created
    }

    // MARK: - Implicit animation values

    /// Whether `value` differs from the one the `.animation(_:value:)` at
    /// `position` last saw. The first sighting is not a change.
    func valueChanged<V: Equatable>(_ value: V, at position: ViewPosition) -> Bool {
        let previous = position.observed?.value(as: V.self)
        guard previous != value else { return false }
        position.observed = Box(value)
        return previous != nil
    }

    // MARK: - Animatable data

    /// The `animatableData` of the view at `position`, moved to `target` —
    /// at once, or over `animation` from wherever it is now.
    func animatableData<Data: VectorArithmetic>(
        at position: ViewPosition,
        target: Data,
        animation: Animation?
    ) -> AnimatableDataState<Data> {
        if let standing = position.animatableData,
           ObjectIdentifier(Swift.type(of: standing)) == ObjectIdentifier(AnimatableDataState<Data>.self) {
            let existing = unsafeDowncast(standing, to: AnimatableDataState<Data>.self)
            existing.update(to: target, animation: animation, in: self)
            return existing
        }
        let created = AnimatableDataState(target)
        position.animatableData = created
        return created
    }

    /// `Animatable` views still between values: rebuilt next frame, at the
    /// value that frame shows. Each is marked, so it is listed once.
    private var rebuilds: [ViewPosition] = []

    func rebuildNextFrame(_ position: ViewPosition) {
        guard !position.rebuildsNextFrame else { return }
        position.rebuildsNextFrame = true
        rebuilds.append(position)
    }

    // MARK: - Transitions

    /// False for a tree rendered as a snapshot (`OffscreenRender`): its
    /// frames never advance, so nothing arrives or leaves — every view is
    /// simply there or not.
    var runsTransitions = true

    /// The slot nodes on their way out. The slots themselves are on their
    /// containers' positions (`ViewPosition.transitionSlots`).
    private var leaving: Set<ObjectIdentifier> = []

    /// Whether any slot is on its way out — what makes every node placed
    /// look among its children for one to draw.
    var hasExits: Bool { !leaving.isEmpty }

    func exitBegan(_ node: ViewNode) {
        leaving.insert(ObjectIdentifier(node))
    }

    /// No longer leaving: its exit ended, or the view came back.
    func exitEnded(_ node: ViewNode) {
        leaving.remove(ObjectIdentifier(node))
    }

    /// Containers whose exits played out this frame, rebuilt the next so
    /// what was left of the views goes.
    private var finishedExits: [ViewPosition] = []

    func exitFinished(_ node: ViewNode, container: ViewPosition?) {
        exitEnded(node)
        if let container { finishedExits.append(container) }
    }

    // MARK: - Timelines

    /// The `TimelineView`s with a moment to come — the moment on each one's
    /// position. One that has another listed once more is harmless: the
    /// first to come up takes the moment.
    private var timelines: [ViewPosition] = []

    func schedule(timelineAt position: ViewPosition, next: Date?) {
        if position.nextTimelineDate == nil, next != nil { timelines.append(position) }
        position.nextTimelineDate = next
    }

    /// Dirty every view that asked to be rebuilt this frame: a timeline
    /// whose moment has come, an `Animatable` view still on its way — and
    /// still there, the same view. Outside any transaction — each redraws;
    /// nothing new starts moving.
    func invalidateScheduledRebuilds() {
        for position in rebuilds where position.rebuildsNextFrame && !position.hasLeft {
            position.rebuildsNextFrame = false
            Invalidator.shared.invalidate(owner: position.path)
        }
        rebuilds.removeAll(keepingCapacity: true)
        // A container whose exit is over, still standing.
        for position in finishedExits where !position.hasLeft && !position.transitionSlots.isEmpty {
            Invalidator.shared.invalidate(owner: position.path)
        }
        finishedExits.removeAll()
        guard !timelines.isEmpty else { return }
        let date = Date()
        timelines.removeAll { position in
            guard !position.hasLeft, let due = position.nextTimelineDate else { return true }
            guard due <= date else { return false }
            position.nextTimelineDate = nil
            Invalidator.shared.invalidate(owner: position.path)
            return true
        }
    }

    // MARK: - Departure

    /// End `exits`, the exits that the containers which left, or which
    /// another view took the place of, were playing. Everything else the
    /// views kept for their animations went with their positions.
    func forget(exits: [ViewNode]) {
        for node in exits {
            exitEnded(node)
        }
    }
}

/// One animatable parameter of a node: a vector of numbers heading for
/// `target`. Shared by every build of the node at its path, so a value a
/// rebuild changes again mid-flight turns from where it is, and as fast as
/// it is going (Motion.swift).
@MainActor
final class AnimatedVector {
    private(set) var target: [Double]
    private var motion: Motion<ComponentVector>?
    /// How fast it moves while changed without animating, for a spring
    /// that takes over (`Transaction.tracksVelocity`).
    private var sampler = VelocitySampler<ComponentVector>()

    init(_ target: [Double]) {
        self.target = target
    }

    func update(to newTarget: [Double], animation: Animation?, in store: AnimationStore) {
        guard newTarget != target else { return }
        if let animation, newTarget.count == target.count {
            let offset = ComponentVector(zip(target, newTarget).map { old, new in old - new })
            motion = Motion.begin(
                offset: offset,
                previous: motion,
                tracked: sampler.velocity(at: store.now),
                animation: animation,
                at: store.now
            )
            if let motion {
                store.noteStarted(motion.run)
            }
            sampler.reset()
        } else {
            motion = nil
            if store.transaction.tracksVelocity, newTarget.count == target.count {
                sampler.add(ComponentVector(newTarget), at: store.now)
            } else {
                sampler.reset()
            }
        }
        target = newTarget
    }

    /// Whether it is still on its way: false once a pass has drawn it
    /// arrived.
    var isMoving: Bool { motion != nil }

    /// The value to draw in the pass under way.
    func current() -> [Double] {
        guard let store = AnimationStore.current else { return target }
        let sample = sample(at: store.now)
        if sample.isFinished {
            motion = nil
        } else {
            store.requestFrame()
        }
        return sample.value
    }

    private func sample(at now: Double) -> (value: [Double], isFinished: Bool) {
        guard let motion else { return (target, true) }
        let left = motion.displacement(at: now)
        guard !left.isFinished else { return (target, true) }
        return (target.indices.map { target[$0] + left.value[$0] }, false)
    }
}

// MARK: - Vectors for the animatable kinds

extension _ResolvedPaint {
    /// A color's components; a gradient changes at once.
    var animatableVector: [Double] {
        guard case .color(let color) = kind else { return [] }
        return [Double(color.red), Double(color.green), Double(color.blue), Double(color.alpha)]
    }

    init(animatableVector v: [Double]) {
        func clamp(_ x: Double) -> Float { Float(Swift.min(Swift.max(x, 0), 1)) }
        self = .color(Color(red: clamp(v[0]), green: clamp(v[1]), blue: clamp(v[2]), opacity: clamp(v[3])))
    }
}

extension BuildContext {
    /// The animated value for `slot` of the view being built, moving to
    /// `target` under this build's transaction.
    func animatedValue(_ slot: AnimationStore.Slot, _ target: [Double]) -> AnimatedVector {
        animations.value(at: position, slot: slot, target: target, animation: transaction.animation)
    }

    /// The animated value for `slot` of the view being built, of a type of
    /// its own, moving to `target` under this build's transaction.
    func animatedState<Data: VectorArithmetic>(_ slot: AnimationStore.Slot, _ target: Data) -> AnimatableDataState<Data> {
        animations.state(at: position, slot: slot, target: target, animation: transaction.animation)
    }

    /// The same for a paint: only a color has anything to animate.
    func animatedPaint(_ slot: AnimationStore.Slot, _ paint: _ResolvedPaint?) -> AnimatedVector? {
        guard let paint else { return nil }
        return animatedValue(slot, paint.animatableVector)
    }
}

extension AnimatedVector {
    /// `paint` as drawn this pass: its color where one is animating.
    func current(of paint: _ResolvedPaint) -> _ResolvedPaint {
        guard case .color = paint.kind else { return paint }
        let vector = current()
        guard vector.count == 4 else { return paint }
        return _ResolvedPaint(animatableVector: vector)
    }
}
