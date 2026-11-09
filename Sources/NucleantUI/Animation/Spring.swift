//
//  Spring.swift
//  NucleantUI
//
//  A damped spring, as SwiftUI's `Spring` is: stored as the three numbers
//  its motion is written in — the damped angular frequency, the decay
//  constant and the mass — with every other way of describing it (duration
//  and bounce, response and damping ratio, stiffness and damping) worked
//  out from those when asked.
//
//  The motion, for a displacement d from the target starting at d₀ with
//  velocity v₀, and ω the damped angular frequency, λ the decay constant:
//
//  * underdamped (ω > 0): d = e^(−λt)·(d₀·cos ωt + (v₀ + λd₀)/ω · sin ωt)
//  * critically damped (ω = 0): d = e^(−λt)·(d₀ + (v₀ + λd₀)·t)
//  * overdamped (ω < 0, holding −ω₀√(ζ²−1)): d = c₁e^(r₁t) + c₂e^(r₂t),
//    with roots r₁ = −ω − λ and r₂ = ω − λ
//
//  Each is linear in d₀ and v₀, so a value of any `VectorArithmetic` type
//  moves as d₀·A(t) + v₀·B(t) with A and B scalars.
//

import Foundation

/// A representation of a spring's motion.
public struct Spring: Hashable, Sendable {

    /// The damped angular frequency. Its sign is the regime: positive
    /// underdamped, zero critically damped, negative overdamped (where it
    /// is −ω₀√(ζ²−1)).
    let angularFrequency: Double

    /// λ = ζ·ω₀: how fast the motion decays.
    let decayConstant: Double

    let storedMass: Double

    private init(angularFrequency: Double, decayConstant: Double, mass: Double) {
        self.angularFrequency = angularFrequency
        self.decayConstant = decayConstant
        self.storedMass = mass
    }

    /// From an undamped angular frequency and a damping ratio, mass 1.
    private init(naturalFrequency omega: Double, dampingRatio zeta: Double) {
        if zeta.isInfinite {
            self.init(angularFrequency: -.infinity, decayConstant: .infinity, mass: 1)
            return
        }
        let sign: Double = zeta > 1 ? -1 : 1
        self.init(
            angularFrequency: sign * omega * abs(1 - zeta * zeta).squareRoot(),
            decayConstant: zeta * omega,
            mass: 1
        )
    }

    /// ω₀², from the stored frequency and decay: λ² + ω² underdamped,
    /// λ² − ω² overdamped.
    private var naturalFrequencySquared: Double {
        decayConstant * decayConstant + angularFrequency * abs(angularFrequency)
    }
}

// MARK: - Duration and bounce

extension Spring {
    /// A spring with a perceptual duration and a bounce: 0 none, up to 1
    /// more and more, below 0 overdamped.
    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) {
        let zeta: Double
        if bounce == 0 {
            zeta = 1
        } else if bounce > 0 {
            zeta = 1 - min(bounce, 1)
        } else if bounce > -1 {
            zeta = 1 / (1 + bounce)
        } else {
            zeta = .infinity
        }
        self.init(naturalFrequency: 2 * .pi / duration, dampingRatio: zeta)
    }

    /// The perceptual duration: the period of the undamped spring.
    public var duration: TimeInterval {
        2 * .pi / naturalFrequencySquared.squareRoot()
    }

    /// How much the spring overshoots: 0 critically damped, toward 1 the
    /// less it is damped, below 0 overdamped.
    public var bounce: Double {
        let zeta = dampingRatio
        return zeta <= 1 ? 1 - zeta : 1 / zeta - 1
    }
}

// MARK: - Response and damping ratio

extension Spring {
    /// A spring with a response — the period of the undamped spring — and a
    /// damping ratio.
    public init(response: Double, dampingRatio: Double) {
        self.init(naturalFrequency: 2 * .pi / response, dampingRatio: dampingRatio)
    }

    public var response: Double {
        duration
    }

    public var dampingRatio: Double {
        decayConstant / naturalFrequencySquared.squareRoot()
    }
}

// MARK: - Physical parameters

extension Spring {
    /// A spring from its physical parameters. Unless `allowOverDamping`, a
    /// damping that would overdamp it makes it critically damped instead.
    public init(mass: Double = 1.0, stiffness: Double, damping: Double, allowOverDamping: Bool = false) {
        let omegaSquared = stiffness / mass
        let omega = omegaSquared.squareRoot()
        let decay = damping / (2 * mass)
        if !allowOverDamping, decay > omega {
            self.init(angularFrequency: 0, decayConstant: omega, mass: mass)
            return
        }
        let sign: Double = decay > omega ? -1 : 1
        self.init(
            angularFrequency: sign * abs(omegaSquared - decay * decay).squareRoot(),
            decayConstant: decay,
            mass: mass
        )
    }

    public var mass: Double {
        storedMass
    }

    public var stiffness: Double {
        storedMass * naturalFrequencySquared
    }

    public var damping: Double {
        2 * storedMass * decayConstant
    }
}

// MARK: - Presets

extension Spring {
    /// No bounce.
    public static var smooth: Spring { smooth() }

    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: extraBounce)
    }

    /// A little bounce.
    public static var snappy: Spring { snappy() }

    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    /// A noticeable bounce.
    public static var bouncy: Spring { bouncy() }

    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}

// MARK: - Motion

extension Spring {
    /// The displacement at `time` as d₀·A + v₀·B, and its rate of change as
    /// d₀·A′ + v₀·B′.
    func coefficients(at time: Double) -> (a: Double, b: Double, da: Double, db: Double) {
        let lambda = decayConstant
        let omega = angularFrequency
        // Infinitely damped: there at once, and still.
        guard lambda.isFinite, omega.isFinite else {
            return time > 0 ? (0, 0, 0, 0) : (1, 0, 0, 1)
        }
        if omega > 0 {
            let decay = exp(-lambda * time)
            let cosine = cos(omega * time), sine = sin(omega * time)
            return (
                a: decay * (cosine + lambda / omega * sine),
                b: decay * sine / omega,
                da: -decay * sine * (omega * omega + lambda * lambda) / omega,
                db: decay * (cosine - lambda / omega * sine)
            )
        }
        if omega == 0 {
            let decay = exp(-lambda * time)
            return (
                a: decay * (1 + lambda * time),
                b: decay * time,
                da: -decay * lambda * lambda * time,
                db: decay * (1 - lambda * time)
            )
        }
        let r1 = -omega - lambda
        let r2 = omega - lambda
        let e1 = exp(r1 * time), e2 = exp(r2 * time)
        let span = r2 - r1
        return (
            a: e1 - r1 * (e2 - e1) / span,
            b: (e2 - e1) / span,
            da: r1 * e1 - r1 * (r2 * e2 - r1 * e1) / span,
            db: (r2 * e2 - r1 * e1) / span
        )
    }

    /// Where a spring that started at zero, moving at `initialVelocity`
    /// toward `target`, is after `time`.
    public func value<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V {
        let c = coefficients(at: time)
        let start = V.zero - target
        return target + start.scaled(by: c.a) + initialVelocity.scaled(by: c.b)
    }

    /// How fast that spring moves after `time`.
    public func velocity<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V {
        let c = coefficients(at: time)
        let start = V.zero - target
        return start.scaled(by: c.da) + initialVelocity.scaled(by: c.db)
    }

    /// Moves `value` and `velocity` on by `deltaTime` toward `target`,
    /// along the spring's exact motion from where they are.
    public func update<V: VectorArithmetic>(value: inout V, velocity: inout V, target: V, deltaTime: TimeInterval) {
        let c = coefficients(at: deltaTime)
        let displacement = value - target
        let newVelocity = displacement.scaled(by: c.da) + velocity.scaled(by: c.db)
        value = target + displacement.scaled(by: c.a) + velocity.scaled(by: c.b)
        velocity = newVelocity
    }

    /// The force the spring exerts at `position` moving at `velocity`:
    /// −stiffness·(position − target) − damping·velocity.
    public func force<V: VectorArithmetic>(target: V, position: V, velocity: V) -> V {
        (target - position).scaled(by: stiffness) - velocity.scaled(by: damping)
    }

    // MARK: Settling

    /// How long until the spring is within a thousandth of a unit target.
    public var settlingDuration: TimeInterval {
        settlingDuration(target: 1.0, initialVelocity: 0.0, epsilon: 0.001)
    }

    /// How long until a spring moving toward `target` stays within
    /// `epsilon` of it — a distance in the value's own units.
    ///
    /// Underdamped, a bound on the envelope: the motion stays within
    /// (|x| + |λx − v₀|)·e^(−λt). Otherwise a search in steps of 0.1 s, up to
    /// 1,024 of them: the first step within `epsilon` that stays within it
    /// for more than a second. Zero if none does, or the motion stops being
    /// finite; infinite for an undamped spring.
    public func settlingDuration<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, epsilon: Double) -> TimeInterval {
        let lambda = decayConstant
        let distance = target.magnitudeSquared.squareRoot()
        let lead = (target.scaled(by: lambda) - initialVelocity).magnitudeSquared.squareRoot()
        return settlingDuration(distance: distance, lead: lead, epsilon: epsilon)
    }

    /// When a running animation of the spring ends: the last moment, at
    /// 120 Hz, the motion is still `epsilon` or more from `target`.
    ///
    /// `settlingDuration` is SwiftUI's figure, and for a bouncing spring an
    /// envelope bound — a fifth or more past the last moment anything
    /// visibly moves (a bounce of 0.3 over 0.5 s: 1.04 s against 0.82 s).
    /// Running to it only draws frames of nothing; SwiftUI's own spring
    /// animations stop on their motion, not on that bound. So start from
    /// it and step back to where the motion last was that far out — a few
    /// dozen evaluations, once per animation.
    func endOfMotion<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, epsilon: Double) -> TimeInterval {
        let bound = settlingDuration(target: target, initialVelocity: initialVelocity, epsilon: epsilon)
        guard bound.isFinite, bound > 0 else { return bound }
        let step = 1.0 / 120
        var time = bound
        while time > step {
            let left = value(target: target, initialVelocity: initialVelocity, time: time - step) - target
            if left.magnitudeSquared.squareRoot() >= epsilon { return time }
            time -= step
        }
        return time
    }

    /// `distance` is |x|, `lead` is |λx − v₀|.
    private func settlingDuration(distance x: Double, lead w: Double, epsilon: Double) -> TimeInterval {
        let lambda = decayConstant
        let omega = angularFrequency
        if lambda == 0 { return .infinity }
        if omega > 0 {
            return max(0, -log(epsilon / (x + w)) / lambda)
        }
        // With v₀ = λx − w, the distance from the target after t.
        let v0 = lambda * x - w
        func remaining(_ t: Double) -> Double {
            if omega == 0 {
                return abs(exp(-lambda * t) * (w * t + x))
            }
            let r1 = -omega - lambda
            let r2 = omega - lambda
            let d0 = -x
            let c2 = (v0 - r1 * d0) / (r2 - r1)
            let c1 = d0 - c2
            return abs(c1 * exp(r1 * t) + c2 * exp(r2 * t))
        }
        var within: Double?
        for step in 0..<1024 {
            let t = Double(step) * 0.1
            let left = remaining(t)
            guard left.isFinite else { return 0 }
            if left < epsilon {
                if let start = within {
                    if t - start > 1 { return start }
                } else {
                    within = t
                }
            } else {
                within = nil
            }
        }
        return 0
    }
}

// MARK: - Animatable values

extension Spring {
    private static func moved<V: Animatable>(_ value: V, to data: V.AnimatableData) -> V {
        var result = value
        result.animatableData = data
        return result
    }

    public func settlingDuration<V: Animatable>(fromValue: V, toValue: V, initialVelocity: V, epsilon: Double) -> TimeInterval {
        settlingDuration(
            target: toValue.animatableData - fromValue.animatableData,
            initialVelocity: initialVelocity.animatableData,
            epsilon: epsilon
        )
    }

    public func value<V: Animatable>(fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval) -> V {
        let travelled = value(
            target: toValue.animatableData - fromValue.animatableData,
            initialVelocity: initialVelocity.animatableData,
            time: time
        )
        return Self.moved(fromValue, to: fromValue.animatableData + travelled)
    }

    public func velocity<V: Animatable>(fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval) -> V {
        let speed = velocity(
            target: toValue.animatableData - fromValue.animatableData,
            initialVelocity: initialVelocity.animatableData,
            time: time
        )
        return Self.moved(fromValue, to: speed)
    }

    public func force<V: Animatable>(fromValue: V, toValue: V, position: V, velocity: V) -> V {
        let pull = force(
            target: toValue.animatableData,
            position: position.animatableData,
            velocity: velocity.animatableData
        )
        return Self.moved(fromValue, to: pull)
    }
}
