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
//    fill color), filed here by path so a rebuild picks up where the last
//    build's value was;
//  * animatable data — an `Animatable` view's, shape's or modifier's own
//    `animatableData` (Animatable.swift): a shape redraws at each value, a
//    view is rebuilt at each, its path dirtied frame by frame until done;
//  * geometry — a node placed somewhere other than where it last stood
//    (`ViewNode.animate`, in NodeMotion.swift);
//  * transitions — a view inserted into, or removed from, an `if`, a
//    `switch`, a `ForEach` or a `for`: its transition's body built around
//    it and moved from phase to phase, the body's own values doing the
//    animating (Transition/TransitionSlots.swift). A removed one stays
//    drawn, out of layout, until everything its exit started is over.
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
    /// so the kinds never collide at a path.
    enum Slot: Hashable {
        case opacity, rotation, scale, offset, move, fill, stroke, textColor
    }

    private var values: [[Int]: [Slot: AnimatedVector]] = [:]

    /// The value for `slot` of the view at `path`, moved to `target` — at
    /// once, or over `animation` from wherever it is now.
    func value(at path: [Int], slot: Slot, target: [Double], animation: Animation?) -> AnimatedVector {
        if let existing = values[path]?[slot] {
            existing.update(to: target, animation: animation, in: self)
            return existing
        }
        let created = AnimatedVector(target)
        values[path, default: [:]][slot] = created
        return created
    }

    // MARK: - Implicit animation values

    /// The last value `.animation(_:value:)` saw at each path.
    private var observed: [[Int]: OpaqueValue] = [:]

    /// Whether `value` differs from the one last seen at `path`. The first
    /// sighting — or a value of another type, a different view now standing
    /// there — is not a change.
    func valueChanged<V: Equatable>(_ value: V, at path: [Int]) -> Bool {
        let previous = observed[path]?.value(as: V.self)
        guard previous != value else { return false }
        observed[path] = OpaqueValue(value)
        return previous != nil
    }

    // MARK: - Animatable data

    /// Each `Animatable` view's or shape's data on its way somewhere, by
    /// path — an `AnimatableDataState` of the type's own data.
    var animatableData: [[Int]: OpaqueReference] = [:]

    /// `Animatable` views still between values: rebuilt next frame, at the
    /// value that frame shows.
    private var animating: Set<[Int]> = []

    func rebuildNextFrame(_ path: [Int]) {
        animating.insert(path)
    }

    // MARK: - Transitions

    /// False for a tree rendered as a snapshot (`OffscreenRender`): its
    /// frames never advance, so nothing arrives or leaves — every view is
    /// simply there or not.
    var runsTransitions = true

    /// The child slots with a transition standing on them, by the path of
    /// their container and their slot in it.
    private var transitionSlots: [[Int]: [Int: TransitionSlot]] = [:]

    func transitionSlots(in container: [Int]) -> [Int: TransitionSlot] {
        transitionSlots[container] ?? [:]
    }

    func setTransitionSlots(_ slots: [Int: TransitionSlot], in container: [Int]) {
        transitionSlots[container] = slots.isEmpty ? nil : slots
    }

    /// The slot nodes on their way out.
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
    private var finishedExits: Set<[Int]> = []

    func exitFinished(_ node: ViewNode, container: [Int]) {
        exitEnded(node)
        finishedExits.insert(container)
    }

    // MARK: - Timelines

    /// When each `TimelineView` wants its content rebuilt next.
    private var timelines: [[Int]: Date] = [:]

    func schedule(timelineAt path: [Int], next: Date?) {
        timelines[path] = next
    }

    /// Dirty every view that asked to be rebuilt this frame: a timeline
    /// whose moment has come, an `Animatable` view still on its way.
    /// Outside any transaction — each redraws; nothing new starts moving.
    func invalidateScheduledRebuilds() {
        for path in animating {
            Invalidator.shared.invalidate(owner: path)
        }
        animating.removeAll(keepingCapacity: true)
        // A container whose exit is over, still standing.
        for path in finishedExits where transitionSlots[path] != nil {
            Invalidator.shared.invalidate(owner: path)
        }
        finishedExits.removeAll()
        guard !timelines.isEmpty else { return }
        let date = Date()
        for (path, due) in timelines where due <= date {
            timelines[path] = nil
            Invalidator.shared.invalidate(owner: path)
        }
    }

    // MARK: - Departure

    /// Drop what the views at `paths` held here — they left the tree.
    func forget(paths: Set<[Int]>) {
        for path in paths {
            values[path] = nil
            observed[path] = nil
            animatableData[path] = nil
            animating.remove(path)
            timelines[path] = nil
            if let slots = transitionSlots.removeValue(forKey: path) {
                for slot in slots.values where slot.isLeaving {
                    exitEnded(slot.node)
                }
            }
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

    init(_ target: [Double]) {
        self.target = target
    }

    func update(to newTarget: [Double], animation: Animation?, in store: AnimationStore) {
        guard newTarget != target else { return }
        if let animation, newTarget.count == target.count {
            let offset = ComponentVector(zip(target, newTarget).map { old, new in old - new })
            motion = Motion.begin(offset: offset, previous: motion, animation: animation, at: store.now)
            if let motion {
                store.noteStarted(motion.run)
            }
        } else {
            motion = nil
        }
        target = newTarget
    }

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

extension ShapeStyle {
    /// Both appearances' components, so a flat color and a dynamic one
    /// animate into each other; a gradient changes at once.
    var animatableVector: [Double] {
        switch self {
        case .color(let color):
            return [color, color].flatMap { [$0.red, $0.green, $0.blue, $0.alpha].map { Double($0) } }
        case .dynamic(let light, let dark):
            return [light, dark].flatMap { [$0.red, $0.green, $0.blue, $0.alpha].map { Double($0) } }
        case .linearGradient, .radialGradient:
            return []
        }
    }

    init(animatableVector v: [Double]) {
        func clamp(_ x: Double) -> Float { Float(Swift.min(Swift.max(x, 0), 1)) }
        let light = Color(red: clamp(v[0]), green: clamp(v[1]), blue: clamp(v[2]), opacity: clamp(v[3]))
        let dark = Color(red: clamp(v[4]), green: clamp(v[5]), blue: clamp(v[6]), opacity: clamp(v[7]))
        self = light == dark ? .color(light) : .dynamic(light: light, dark: dark)
    }
}

extension BuildContext {
    /// The animated value for `slot` of the view being built, moving to
    /// `target` under this build's transaction.
    func animatedValue(_ slot: AnimationStore.Slot, _ target: [Double]) -> AnimatedVector {
        animations.value(at: path, slot: slot, target: target, animation: transaction.animation)
    }

    /// The same for a paint: only a flat or dynamic color has anything to
    /// animate.
    func animatedStyle(_ slot: AnimationStore.Slot, _ style: ShapeStyle?) -> AnimatedVector? {
        guard let style else { return nil }
        return animatedValue(slot, style.animatableVector)
    }
}

extension AnimatedVector {
    /// `style` as drawn this pass: its color where one is animating.
    func current(of style: ShapeStyle) -> ShapeStyle {
        switch style {
        case .color, .dynamic: break
        case .linearGradient, .radialGradient: return style
        }
        let vector = current()
        guard vector.count == 8 else { return style }
        return ShapeStyle(animatableVector: vector)
    }
}
