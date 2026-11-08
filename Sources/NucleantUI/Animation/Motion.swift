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
    /// `previous` what the value was doing toward the old target. `nil`
    /// when a spring has nothing to do: the value is at the new target and
    /// not moving.
    static func begin(
        offset: Value,
        previous: Motion<Value>?,
        animation: Animation,
        at now: Double
    ) -> Motion<Value>? {
        let running = previous.flatMap { $0.run.isDone(at: now) ? nil : $0 }

        guard case .spring(let spring, let unitVelocity, _) = animation.curve, animation.repeatCount == 1 else {
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
