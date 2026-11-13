//
//  Animatable.swift
//  NucleantUI
//
//  The protocols a type adopts to animate its *own* values — SwiftUI's
//  `Animatable` and `VectorArithmetic`. A view, a shape or a view modifier
//  exposes `animatableData`; when a change gives it a new value under an
//  animation, the framework hands it every value in between, one frame at
//  a time: a shape redraws its path at each (no rebuild — see
//  `_ShapeView`), a view or modifier has its body rebuilt at each.
//

import Foundation

// MARK: - VectorArithmetic

/// A value that can be interpolated: added, subtracted and scaled.
public protocol VectorArithmetic: AdditiveArithmetic {
    /// Multiplies each component by `rhs`.
    mutating func scale(by rhs: Double)

    /// The dot product of the value with itself.
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    /// A copy with each component multiplied by `rhs`.
    public func scaled(by rhs: Double) -> Self {
        var copy = self
        copy.scale(by: rhs)
        return copy
    }

    /// `from` moved `fraction` of the way to `to` — 0 is `from`, 1 is `to`,
    /// and outside 0…1 overshoots, as a spring does.
    static func interpolate(from: Self, to: Self, fraction: Double) -> Self {
        from + (to - from).scaled(by: fraction)
    }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}

extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

/// Two animatable values animated together — how a type with more than one
/// animatable property exposes them as one `animatableData`.
@frozen
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: Self { Self(.zero, .zero) }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    public static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }

    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }

    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}

/// Nothing to animate — the `animatableData` of a type that has none.
@frozen
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    public init() {}

    public static var zero: Self { Self() }
    public static func + (lhs: Self, rhs: Self) -> Self { lhs }
    public static func - (lhs: Self, rhs: Self) -> Self { lhs }
    public static func += (lhs: inout Self, rhs: Self) {}
    public static func -= (lhs: inout Self, rhs: Self) {}
    public mutating func scale(by rhs: Double) {}
    public var magnitudeSquared: Double { 0 }
}

// MARK: - Animatable

/// A type that animates its own values.
///
/// ```swift
/// @View
/// struct Countdown: Animatable {
///     var value: Double
///     var animatableData: Double {
///         get { value }
///         set { value = newValue }
///     }
///     var body: some View { Text("\(Int(value))") }
/// }
///
/// Countdown(value: done ? 0 : 10)
///     .animation(.linear(duration: 2), value: done)   // 10, 9, 8 … 0
/// ```
///
/// Every `Shape` is `Animatable`; one with nothing to animate gets
/// `EmptyAnimatableData` by default.
@MainActor @preconcurrency
public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic

    /// The values to interpolate.
    var animatableData: AnimatableData { get set }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self {
        get { self }
        set { self = newValue }
    }
}

/// A view modifier that animates its own values — SwiftUI's name for
/// `ViewModifier & Animatable`, kept for source compatibility.
@MainActor @preconcurrency
public protocol AnimatableModifier: Animatable, ViewModifier {}

/// A view made with an animatable modifier animates through it.
extension ModifiedContent: Animatable where Modifier: Animatable {
    public var animatableData: Modifier.AnimatableData {
        get { modifier.animatableData }
        set { modifier.animatableData = newValue }
    }
}

// MARK: - Geometry

extension Angle: Animatable {
    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}

/// `Point` and `Size` both.
extension SIMD2: Animatable where Scalar == Double {
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set { (x, y) = (newValue.first, newValue.second) }
    }
}

extension Rect: Animatable {
    public var animatableData: AnimatablePair<Point.AnimatableData, Size.AnimatableData> {
        get { AnimatablePair(origin.animatableData, size.animatableData) }
        set {
            origin.animatableData = newValue.first
            size.animatableData = newValue.second
        }
    }
}

extension UnitPoint: Animatable {
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set { (x, y) = (newValue.first, newValue.second) }
    }
}

extension EdgeInsets: Animatable {
    public var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get { AnimatablePair(top, AnimatablePair(leading, AnimatablePair(bottom, trailing))) }
        set {
            top = newValue.first
            leading = newValue.second.first
            bottom = newValue.second.second.first
            trailing = newValue.second.second.second
        }
    }
}

// MARK: - Driving animatable data

/// What `AnimationStore.animatableData` holds for a view or shape of any
/// animatable type: an `AnimatableDataState` of that type's data, taken back
/// out as what it is.
@MainActor
class AnyAnimatableDataState {}

/// One path's `animatableData` on its way to `target`. Shared by every
/// build of the view at that path, so a change mid-flight turns from where
/// the value is showing, and as fast as it is going (Motion.swift).
@MainActor
final class AnimatableDataState<Data: VectorArithmetic>: AnyAnimatableDataState {
    private(set) var target: Data
    private var motion: Motion<Data>?
    /// How fast it moves while changed without animating, for a spring
    /// that takes over (`Transaction.tracksVelocity`).
    private var sampler = VelocitySampler<Data>()

    init(_ target: Data) {
        self.target = target
    }

    func update(to newTarget: Data, animation: Animation?, in store: AnimationStore) {
        guard newTarget != target else { return }
        if let animation {
            motion = Motion.begin(
                offset: target - newTarget,
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
            if store.transaction.tracksVelocity {
                sampler.add(newTarget, at: store.now)
            } else {
                sampler.reset()
            }
        }
        target = newTarget
    }

    /// The value to draw in the pass under way, asking for another frame
    /// while it is still on its way.
    func current() -> Data {
        guard let store = AnimationStore.current else { return target }
        let sample = sample(at: store.now)
        if !sample.isFinished { store.requestFrame() }
        return sample.value
    }

    /// The value showing at `now`, and whether it has arrived.
    func sample(at now: Double) -> (value: Data, isFinished: Bool) {
        guard let motion else { return (target, true) }
        let left = motion.displacement(at: now)
        if left.isFinished {
            self.motion = nil
            return (target, true)
        }
        return (target + left.value, false)
    }
}

extension AnimationStore {

    /// `value` with its `animatableData` at what is showing in this frame,
    /// having moved it towards the value just built under `animation`.
    /// `isFinished` is false while it is still on its way.
    func animated<A: Animatable>(
        _ value: A,
        at path: [Int],
        animation: Animation?
    ) -> (value: A, isFinished: Bool) {
        guard A.AnimatableData.self != EmptyAnimatableData.self else { return (value, true) }
        let target = value.animatableData
        let state: AnimatableDataState<A.AnimatableData>
        if let existing = animatableData[path] as? AnimatableDataState<A.AnimatableData> {
            state = existing
            state.update(to: target, animation: animation, in: self)
        } else {
            state = AnimatableDataState(target)
            animatableData[path] = state
        }
        let sample = state.sample(at: now)
        var shown = value
        shown.animatableData = sample.value
        return (shown, sample.isFinished)
    }
}

extension BuildContext {

    /// A view about to have its body evaluated, as it should show in this
    /// frame: an `Animatable` one with its data part of the way to where
    /// it is going, and its path dirtied for the next frame until it gets
    /// there. Everything else as it is.
    func showing<V: View>(_ view: V) -> V {
        let type = ObjectIdentifier(V.self)
        guard !_AnimatableTypes.inanimate.contains(type) else { return view }
        // A shape animates where it is drawn (`drawnShape`), which needs no
        // rebuild; its body only hands it on.
        guard !(view is any Shape), let animatable = view as? any Animatable else {
            _AnimatableTypes.inanimate.insert(type)
            return view
        }
        return showing(animatable: animatable) as? V ?? view
    }

    private func showing<A: Animatable>(animatable: A) -> A {
        let result = animations.animated(animatable, at: path, animation: transaction.animation)
        if !result.isFinished {
            animations.rebuildNextFrame(path)
        }
        return result.value
    }

    /// A shape's paint for the node being built, when it is an animatable
    /// one on its way somewhere: the shape as it stands at the moment of
    /// drawing. No rebuild: the path is simply made again at each frame's
    /// value, and the node asks for the frames it needs. `nil` for a shape
    /// that is where it was built — drawn as it is.
    func drawnShape<S: Shape>(_ shape: S) -> (@MainActor () -> S)? {
        guard S.AnimatableData.self != EmptyAnimatableData.self else { return nil }
        let result = animations.animated(shape, at: path, animation: transaction.animation)
        guard !result.isFinished,
              let state = animations.animatableData[path] as? AnimatableDataState<S.AnimatableData>
        else { return nil }
        return {
            guard let store = AnimationStore.current else { return shape }
            let sample = state.sample(at: store.now)
            if !sample.isFinished { store.requestFrame() }
            var drawn = shape
            drawn.animatableData = sample.value
            return drawn
        }
    }
}

/// View types known to have nothing animatable — asked once per type.
@MainActor
enum _AnimatableTypes {
    static var inanimate: Set<ObjectIdentifier> = []
}

// MARK: - Type-erased storage

/// A value of a type only the call site knows, in an object of its own —
/// one allocation, the value stored in it — taken back out only as the
/// type it is. How the effect queue, the preference cache and the stores
/// keep values of many types side by side.
class AnyBox: @unchecked Sendable {
    /// The value, if it is a `T`.
    final func value<T>(as _: T.Type) -> T? {
        (self as? Box<T>)?.value
    }
}

final class Box<T>: AnyBox, @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}
