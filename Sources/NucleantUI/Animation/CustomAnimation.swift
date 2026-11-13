//
//  CustomAnimation.swift
//  NucleantUI
//
//  Animations written outside the framework — SwiftUI's `CustomAnimation`
//  and the context and per-animation state it is handed each frame — and
//  `AnimationRun`, one animation in flight, which is what keeps that state
//  from one frame to the next.
//

import Foundation

/// An animation curve of your own, wrapped in `Animation(_:)` to use it.
///
/// ```swift
/// struct Stepped: CustomAnimation {
///     var steps = 5
///     var duration = 1.0
///
///     func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
///         guard time < duration else { return nil }
///         let step = (time / duration * Double(steps)).rounded(.down)
///         return value.scaled(by: step / Double(steps))
///     }
/// }
///
/// withAnimation(Animation(Stepped())) { progress = 1 }
/// ```
public protocol CustomAnimation: Hashable, Sendable {

    /// How much of the change `value` — the new value less the old — has
    /// happened `time` seconds in, or `nil` once the animation is over.
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V?

    /// The rate of change at `time`, when the animation can say.
    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V?

    /// Whether a new animation of the same value, arriving while this one
    /// runs, should be folded into it rather than replace it.
    func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool
}

extension CustomAnimation {
    public func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        nil
    }

    public func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool {
        false
    }
}

/// What a custom animation is handed each frame, and may change.
public struct AnimationContext<Value: VectorArithmetic> {

    /// Values the animation keeps between frames.
    public var state: AnimationState<Value>

    /// Set by the animation once the value has visibly arrived, though the
    /// curve may still be settling — what `withAnimation`'s completion
    /// waits for.
    public var isLogicallyComplete: Bool

    init(state: AnimationState<Value> = AnimationState(), isLogicallyComplete: Bool = false) {
        self.state = state
        self.isLogicallyComplete = isLogicallyComplete
    }

    /// The same context carrying `state` — for an animation that runs
    /// another over a different value type.
    public func withState<T: VectorArithmetic>(_ state: AnimationState<T>) -> AnimationContext<T> {
        AnimationContext<T>(state: state, isLogicallyComplete: isLogicallyComplete)
    }
}

/// A custom animation's own storage, keyed by `AnimationStateKey` types.
public struct AnimationState<Value: VectorArithmetic> {
    var storage: [ObjectIdentifier: AnyBox] = [:]

    public init() {}

    public subscript<K: AnimationStateKey>(key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)]?.value(as: K.Value.self) ?? K.defaultValue }
        // A fresh box per write, so a copy of the state keeps its own value.
        set { storage[ObjectIdentifier(key)] = Box(newValue) }
    }

    /// The same storage, seen as state for another value type.
    func retyped<T: VectorArithmetic>() -> AnimationState<T> {
        var state = AnimationState<T>()
        state.storage = storage
        return state
    }
}

/// A key into `AnimationState`, and the value it holds before it is set.
public protocol AnimationStateKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

extension Animation {
    /// An animation that runs `base`.
    public init<A: CustomAnimation>(_ base: A) {
        self.init(curve: .custom(CustomCurve(base)))
    }

    /// How much of `value` has happened `time` seconds into this
    /// animation, or `nil` once it is over — so a custom animation can run
    /// another inside it.
    public func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        if case .custom(let custom) = curve {
            var inner = AnimationContext<Double>(state: context.state.retyped(), isLogicallyComplete: context.isLogicallyComplete)
            let fraction = custom.animate(localTime(time), &inner)
            context.state = inner.state.retyped()
            context.isLogicallyComplete = inner.isLogicallyComplete
            return fraction.map { value.scaled(by: $0) }
        }
        let progress = progress(after: time)
        return progress.isFinished ? nil : value.scaled(by: progress.fraction)
    }

    /// Never known for the built-in curves.
    public func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        nil
    }

    /// Whether a new animation arriving over this one folds into it.
    public func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> Bool {
        false
    }
}

/// A `CustomAnimation` inside `Animation`, which must stay `Hashable` and
/// `Sendable` without knowing the type: the base is captured by closures,
/// and compared with another by handing a pointer to that other's base —
/// read only once its type is confirmed to match.
struct CustomCurve: Hashable, Sendable {
    private let type: ObjectIdentifier
    private let hash: Int
    /// Drives the base on the unit change: the fraction done, or `nil`.
    let animate: @Sendable (Double, inout AnimationContext<Double>) -> Double?
    /// Whether the base behind a pointer equals this one's.
    private let matches: @Sendable (UnsafeRawPointer) -> Bool
    /// Hands a pointer to this one's base to `body`.
    private let withBase: @Sendable ((UnsafeRawPointer) -> Bool) -> Bool

    init<A: CustomAnimation>(_ base: A) {
        type = ObjectIdentifier(A.self)
        var hasher = Hasher()
        hasher.combine(type)
        hasher.combine(base)
        hash = hasher.finalize()
        animate = { time, context in base.animate(value: 1.0, time: time, context: &context) }
        matches = { pointer in pointer.assumingMemoryBound(to: A.self).pointee == base }
        withBase = { body in withUnsafePointer(to: base) { body(UnsafeRawPointer($0)) } }
    }

    static func == (lhs: CustomCurve, rhs: CustomCurve) -> Bool {
        lhs.type == rhs.type && rhs.withBase(lhs.matches)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }
}

// MARK: - Running

/// One animation in flight, from the moment it started. Holds what a
/// custom animation keeps between frames; a built-in curve needs nothing
/// but the clock.
@MainActor
final class AnimationRun {
    let animation: Animation
    /// When the curve's clock started: the frame that started the run,
    /// until a later frame settles it (`settleStart(at:)`).
    private(set) var start: Double
    private var isStartSettled = false
    private var context = AnimationContext<Double>()
    private var customFinished = false

    /// The most of the curve the first frame after the one that started a
    /// run may show: two frames at 60 Hz.
    static let longestFirstStep = 2.0 / 60

    init(_ animation: Animation, start: Double) {
        self.animation = animation
        self.start = start
    }

    /// The frame that starts a run shows it at its beginning. If the next
    /// frame comes late — the change built a lot, so the frame it was made
    /// in took long — the start moves up to `longestFirstStep` before it,
    /// so the motion begins where the curve does rather than part-way in.
    /// A frame on time leaves it where it was.
    private func settleStart(at now: Double) {
        guard !isStartSettled, now > start else { return }
        isStartSettled = true
        start = max(start, now - Self.longestFirstStep)
    }

    /// Real seconds since the curve's clock started.
    func elapsed(at now: Double) -> Double {
        settleStart(at: now)
        return now - start
    }

    /// The fraction of the change done at `now`, and whether it is over.
    func progress(at now: Double) -> (fraction: Double, isFinished: Bool) {
        let elapsed = elapsed(at: now)
        guard case .custom(let custom) = animation.curve else {
            return animation.progress(after: elapsed)
        }
        guard !customFinished else { return (1, true) }
        let time = animation.localTime(elapsed)
        guard time > 0 else { return (0, false) }
        guard let fraction = custom.animate(time, &context) else {
            customFinished = true
            return (1, true)
        }
        return (fraction, false)
    }

    /// How fast the fraction changes at `now`, per real second. Zero for a
    /// custom curve, which can only be run forward, one frame at a time.
    func rate(at now: Double) -> Double {
        guard !isDone(at: now) else { return 0 }
        if case .custom = animation.curve { return 0 }
        let elapsed = elapsed(at: now)
        let step = 0.001
        let ahead = animation.progress(after: elapsed + step).fraction
        let behind = animation.progress(after: max(0, elapsed - step)).fraction
        return (ahead - behind) / (elapsed + step - max(0, elapsed - step))
    }

    /// Whether it is over by `now` — by the clock for a built-in curve;
    /// for a custom one, once it has said so (or called itself logically
    /// complete) the last time it ran.
    func isDone(at now: Double) -> Bool {
        guard case .custom = animation.curve else {
            return elapsed(at: now) >= animation.totalDuration
        }
        return customFinished || context.isLogicallyComplete
    }

    /// Whether the value has visibly arrived by `now`, though the curve
    /// may still be settling — as SwiftUI judges it:
    ///
    /// * a time given with `logicallyComplete(after:)`, after the delay;
    /// * a spring played once, one response in — the rest of its motion is
    ///   the settling;
    /// * a custom curve, once it has said so;
    /// * anything else, once it is over. A repeat that never ends never is.
    func isLogicallyComplete(at now: Double) -> Bool {
        if isDone(at: now) { return true }
        let elapsed = elapsed(at: now)
        if let time = animation.logicalCompletionTime {
            return elapsed - animation.delay >= time
        }
        if case .spring(let spring, _, _) = animation.curve, animation.repeatCount == 1 {
            return animation.localTime(elapsed) >= spring.response
        }
        return false
    }

    /// True for a repeat that never ends — nothing waits on it.
    var isEndless: Bool {
        animation.repeatCount == nil
    }
}
