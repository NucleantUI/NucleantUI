//
//  Motion.swift
//  NucleantUI
//
//  A value on its way to its target, kept as what is still left to go: a
//  displacement from the target that runs out. What is drawn is the target
//  plus that displacement.
//
//  A value given a new target while it is still moving does not start
//  again from rest:
//
//  * under a spring, the new motion starts from where the value is *and*
//    how fast it is going. A spring's motion is linear in its starting
//    displacement d₀ and velocity v₀ (d = d₀·A(t) + v₀·B(t), Spring.swift),
//    so a vector of any length still costs two scalar evaluations;
//  * under any other curve, the motion under way keeps running, and the
//    new one carries the value from wherever that one has got to, to the
//    new target: d = (Δ + d_old(t))·(1 − f(t)), Δ being how far the old
//    target is from the new. Once the old motion is over it is dropped.
//
//  SwiftUI does the same: a spring merges into what was running, keeping
//  its velocity, and another curve is combined with it.
//

import Foundation

/// What is still left of a value's way to its target.
@MainActor
final class Motion<Value: VectorArithmetic> {

    /// The animation the motion runs on.
    let run: AnimationRun

    /// The displacement it started from.
    private let offset: Value

    /// For a spring: the spring, and how fast the displacement was changing
    /// as it started, per second of the curve's own time.
    private let spring: Spring?
    private let initialVelocity: Value

    /// For any other curve: the motion that was under way when this one
    /// began, still running toward the old target, which `offset` is the
    /// distance from.
    private var underlying: Motion<Value>?

    private init(run: AnimationRun, offset: Value, spring: Spring?, initialVelocity: Value, underlying: Motion<Value>?) {
        self.run = run
        self.offset = offset
        self.spring = spring
        self.initialVelocity = initialVelocity
        self.underlying = underlying
    }

    /// The motion toward a new target under `animation`, starting at `now`.
    ///
    /// `offset` is how far the old target is from the new one, and
    /// `previous` what the value was doing toward the old target.
    /// `tracked` is how fast the value was moving, per second, when it was
    /// last changed without animating (`Transaction.tracksVelocity`) — a
    /// spring sets off at it when nothing is running. `nil` when a spring
    /// has nothing to do: the value is at the new target and not moving.
    static func begin(
        offset: Value,
        previous: Motion<Value>?,
        tracked: Value? = nil,
        animation: Animation,
        at now: Double
    ) -> Motion<Value>? {
        // A repeat that never ends is not kept running beneath: it would
        // never let go, and each new target would nest another. The new
        // motion starts from where it shows the value, standing still.
        var offset = offset
        var running = previous.flatMap { $0.run.isDone(at: now) ? nil : $0 }
        if let endless = running, endless.run.isEndless {
            offset += endless.displacement(at: now).value
            running = nil
        }

        // A spring played once takes over what is running, as SwiftUI's
        // merges — but, as there, only from an animation with the same
        // delay and speed. Otherwise the two are combined, and the old
        // motion runs on through the new one's delay.
        let merges = running.map {
            $0.run.animation.delay == animation.delay && $0.run.animation.speed == animation.speed
        } ?? true
        guard case .spring(let spring, let unitVelocity, _) = animation.curve, animation.repeatCount == 1, merges else {
            return Motion(
                run: AnimationRun(animation, start: now),
                offset: offset,
                spring: nil,
                initialVelocity: .zero,
                underlying: running
            )
        }

        // Where the value stands from the new target, and how fast it is
        // going — per second of the curve's time, so divided by its speed —
        // plus the velocity the animation was given, in units of the change.
        var start = offset
        var velocity = Value.zero
        if let running {
            start += running.displacement(at: now).value
            velocity = running.velocity(at: now).scaled(by: 1 / animation.speed)
        } else if let tracked {
            velocity = tracked.scaled(by: 1 / animation.speed)
        }
        velocity -= start.scaled(by: unitVelocity)

        // Settled within a thousandth of the motion's own size — the
        // distance to go, or the swing the velocity alone would make.
        let size = max(
            start.magnitudeSquared.squareRoot(),
            velocity.magnitudeSquared.squareRoot() * spring.response / (2 * .pi)
        )
        guard size > 0 else { return nil }
        let settling = spring.settlingDuration(target: .zero - start, initialVelocity: velocity, epsilon: size * 0.001)
        var settled = animation
        settled.curve = .spring(spring, initialVelocity: unitVelocity, settlingDuration: settling)

        return Motion(
            run: AnimationRun(settled, start: now),
            offset: start,
            spring: spring,
            initialVelocity: velocity,
            underlying: nil
        )
    }

    /// What is left at `now`, and whether the motion is over.
    func displacement(at now: Double) -> (value: Value, isFinished: Bool) {
        if let spring {
            guard !run.isDone(at: now) else { return (.zero, true) }
            let time = run.animation.localTime(run.elapsed(at: now))
            guard time > 0 else { return (offset, false) }
            let moved = spring.value(target: .zero - offset, initialVelocity: initialVelocity, time: time)
            return (moved + offset, false)
        }
        let progress = run.progress(at: now)
        guard !progress.isFinished else {
            underlying = nil
            return (.zero, true)
        }
        return (from(at: now).scaled(by: 1 - progress.fraction), false)
    }

    /// How fast the displacement changes at `now`, per real second.
    func velocity(at now: Double) -> Value {
        guard !run.isDone(at: now) else { return .zero }
        if let spring {
            // Still in its delay: holding still.
            let time = run.animation.localTime(run.elapsed(at: now))
            guard time >= 0 else { return .zero }
            return spring.velocity(target: .zero - offset, initialVelocity: initialVelocity, time: time)
                .scaled(by: run.animation.speed)
        }
        // d = s·(1 − f), with s the old target's distance plus what is
        // left of the motion below: d′ = s′·(1 − f) − s·f′.
        let fraction = run.progress(at: now).fraction
        let rate = run.rate(at: now)
        let below = underlying?.velocity(at: now) ?? .zero
        return below.scaled(by: 1 - fraction) - from(at: now).scaled(by: rate)
    }

    /// Where the value is coming from, measured from the target: the old
    /// target, plus what is left of the motion toward it.
    private func from(at now: Double) -> Value {
        guard let below = underlying else { return offset }
        let left = below.displacement(at: now)
        if left.isFinished {
            underlying = nil
            return offset
        }
        return offset + left.value
    }
}

/// How fast a value is moving while it is changed without animating, under
/// `Transaction.tracksVelocity` — a drag — from its last three changes, as
/// SwiftUI's `VelocitySampler` keeps them. The newer pair of changes counts
/// for a quarter and the older for three quarters. The speed fades by 0.2%
/// a millisecond after the last change, and is forgotten 2 s after it.
///
/// SwiftUI drives its sampling with an animation that asks for frames for
/// those 2 s; here the samples simply sit beside the value until an
/// animated change asks for them, and no frame is drawn for them.
struct VelocitySampler<Value: VectorArithmetic> {
    private var samples: [(value: Value, time: Double)] = []

    /// Whether there is nothing to forget.
    var isEmpty: Bool { samples.isEmpty }

    /// Notes that the value is `value` at `time`. A second change in the
    /// same frame replaces the first.
    mutating func add(_ value: Value, at time: Double) {
        if let last = samples.last {
            guard time >= last.time else { return }
            if time - last.time < .ulpOfOne {
                samples[samples.count - 1] = (value, time)
                return
            }
        }
        samples.append((value, time))
        if samples.count > 3 { samples.removeFirst() }
    }

    mutating func reset() {
        samples.removeAll()
    }

    /// The value's speed per second at `now`, or `nil` with fewer than two
    /// changes or the last more than 2 s ago.
    func velocity(at now: Double) -> Value? {
        guard samples.count >= 2, let last = samples.last, now - last.time < 2 else { return nil }
        func between(_ a: (value: Value, time: Double), _ b: (value: Value, time: Double)) -> Value {
            (b.value - a.value).scaled(by: 1 / (b.time - a.time))
        }
        let n = samples.count
        var velocity = between(samples[n - 2], samples[n - 1])
        if n == 3 {
            let older = between(samples[0], samples[1])
            velocity += (older - velocity).scaled(by: 0.75)
        }
        return velocity.scaled(by: pow(0.998, (now - last.time) * 1000))
    }
}

/// A list of numbers as one `VectorArithmetic` value — a modifier's
/// parameters, which `AnimatedVector` keeps as an array. Missing
/// components count as zero, so `.zero` is the empty list.
struct ComponentVector: VectorArithmetic {
    var components: [Double]

    init(_ components: [Double]) {
        self.components = components
    }

    static var zero: ComponentVector { ComponentVector([]) }

    private static func combine(_ lhs: ComponentVector, _ rhs: ComponentVector, _ op: (Double, Double) -> Double) -> ComponentVector {
        let count = max(lhs.components.count, rhs.components.count)
        return ComponentVector((0..<count).map { i in
            op(lhs[i], rhs[i])
        })
    }

    /// Component `i`, or zero past the end.
    subscript(i: Int) -> Double {
        i < components.count ? components[i] : 0
    }

    static func + (lhs: ComponentVector, rhs: ComponentVector) -> ComponentVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: ComponentVector, rhs: ComponentVector) -> ComponentVector {
        combine(lhs, rhs, -)
    }

    static func == (lhs: ComponentVector, rhs: ComponentVector) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        return (0..<count).allSatisfy { lhs[$0] == rhs[$0] }
    }

    mutating func scale(by rhs: Double) {
        for i in components.indices {
            components[i] *= rhs
        }
    }

    var magnitudeSquared: Double {
        components.reduce(0) { $0 + $1 * $1 }
    }
}
