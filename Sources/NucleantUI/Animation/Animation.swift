//
//  Animation.swift
//  NucleantUI
//
//  How a change travels from its old value to its new one: a curve over
//  time, plus the delay, speed and repetition applied to it. A value type
//  with no clock of its own — whatever animates asks it for the fraction
//  done at some elapsed time (`progress(after:)`), so one `Animation` can
//  drive any number of values started at different moments.
//

import Foundation

/// The way a view changes over time — SwiftUI's `Animation`.
///
/// ```swift
/// withAnimation(.spring(duration: 0.4, bounce: 0.2)) { isExpanded.toggle() }
/// Circle().scaleEffect(pulse ? 1.2 : 1)
///     .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
/// ```
public struct Animation: Hashable, Sendable {

    enum Curve: Hashable, Sendable {
        /// A cubic Bézier from (0, 0) to (1, 1) through the two control
        /// points — `linear` is (0, 0, 1, 1).
        case timing(x1: Double, y1: Double, x2: Double, y2: Double, duration: Double)
        /// A spring travelling from 0 to 1, starting at `initialVelocity`
        /// (in units of the whole change per second), and how long it takes
        /// to settle — worked out once, not on every frame that asks.
        case spring(Spring, initialVelocity: Double, settlingDuration: Double)
        /// A `CustomAnimation` — see `Animation(_:)`.
        case custom(CustomCurve)
    }

    var curve: Curve
    /// Real seconds before the curve starts moving.
    var delay: Double = 0
    /// How fast the curve's own clock runs relative to real time.
    var speed: Double = 1
    /// How many times the curve plays; `nil` is forever.
    var repeatCount: Int? = 1
    /// Every other repetition plays backwards.
    var autoreverses = false

    init(curve: Curve) {
        self.curve = curve
    }

    // MARK: - Timing curves

    /// A default animation: a bounceless spring with a half-second
    /// response, as SwiftUI's default has been since its springs became it.
    public static let `default` = Animation.spring(Spring(response: 0.5, dampingRatio: 1))

    public static func linear(duration: Double) -> Animation {
        timingCurve(0, 0, 1, 1, duration: duration)
    }

    public static var linear: Animation { linear(duration: 0.35) }

    public static func easeIn(duration: Double) -> Animation {
        timingCurve(0.42, 0, 1, 1, duration: duration)
    }

    public static var easeIn: Animation { easeIn(duration: 0.35) }

    public static func easeOut(duration: Double) -> Animation {
        timingCurve(0, 0, 0.58, 1, duration: duration)
    }

    public static var easeOut: Animation { easeOut(duration: 0.35) }

    public static func easeInOut(duration: Double) -> Animation {
        timingCurve(0.42, 0, 0.58, 1, duration: duration)
    }

    public static var easeInOut: Animation { easeInOut(duration: 0.35) }

    /// A cubic Bézier timing curve through control points `(p1x, p1y)` and
    /// `(p2x, p2y)`, the way CSS and Core Animation spell one.
    public static func timingCurve(
        _ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
        duration: Double = 0.35
    ) -> Animation {
        Animation(curve: .timing(
            x1: min(max(p1x, 0), 1), y1: p1y,
            x2: min(max(p2x, 0), 1), y2: p2y,
            duration: max(0, duration)
        ))
    }

    // MARK: - Springs

    static func spring(_ spring: Spring, initialVelocity: Double) -> Animation {
        Animation(curve: .spring(
            spring,
            initialVelocity: initialVelocity,
            settlingDuration: spring.settlingDuration(target: 1.0, initialVelocity: initialVelocity, epsilon: 0.001)
        ))
    }

    /// An animation along `spring`.
    public static func spring(_ spring: Spring, blendDuration: Double = 0) -> Animation {
        Animation.spring(spring, initialVelocity: 0)
    }

    /// A spring described by how long it takes to settle and how much it
    /// bounces: 0 is critically damped, up to 1 undamped, and down to -1
    /// increasingly overdamped.
    public static func spring(duration: Double = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
        spring(Spring(duration: duration, bounce: bounce), blendDuration: blendDuration)
    }

    /// A spring described by its response (roughly, its period in seconds)
    /// and the fraction of critical damping applied to it.
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation {
        spring(Spring(response: response, dampingRatio: dampingFraction), blendDuration: blendDuration)
    }

    public static var spring: Animation { spring(duration: 0.5, bounce: 0) }

    /// A stiffer spring, for following a finger.
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation {
        spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }

    public static var interactiveSpring: Animation { interactiveSpring() }

    /// A spring with no bounce.
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        spring(.smooth(duration: duration, extraBounce: extraBounce))
    }

    public static var smooth: Animation { smooth() }

    /// A spring with a little bounce.
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        spring(.snappy(duration: duration, extraBounce: extraBounce))
    }

    public static var snappy: Animation { snappy() }

    /// A spring with a visible bounce.
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        spring(.bouncy(duration: duration, extraBounce: extraBounce))
    }

    public static var bouncy: Animation { bouncy() }

    /// A spring given as the physics: mass, stiffness and damping, with an
    /// initial velocity in units of the whole change per second. Damping
    /// that would overdamp it makes it critically damped, as
    /// `Spring(mass:stiffness:damping:)` does.
    public static func interpolatingSpring(
        mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0
    ) -> Animation {
        spring(Spring(mass: mass, stiffness: stiffness, damping: damping), initialVelocity: initialVelocity)
    }

    public static func interpolatingSpring(duration: Double = 0.5, bounce: Double = 0, initialVelocity: Double = 0) -> Animation {
        spring(Spring(duration: duration, bounce: bounce), initialVelocity: initialVelocity)
    }

    /// An animation along `spring`, starting at `initialVelocity`.
    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0) -> Animation {
        Animation.spring(spring, initialVelocity: initialVelocity)
    }

    public static var interpolatingSpring: Animation { interpolatingSpring() }

    // MARK: - Modifiers

    /// Waits `delay` seconds before starting.
    public func delay(_ delay: Double) -> Animation {
        var copy = self
        copy.delay += max(0, delay)
        return copy
    }

    /// Runs `speed` times as fast — 2 is twice as fast, 0.5 half.
    public func speed(_ speed: Double) -> Animation {
        var copy = self
        copy.speed *= max(speed, .leastNonzeroMagnitude)
        return copy
    }

    /// Plays `repeatCount` times, every other one backwards when
    /// `autoreverses`. Ends on the new value whichever way the last one ran.
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        var copy = self
        copy.repeatCount = max(1, repeatCount)
        copy.autoreverses = autoreverses
        return copy
    }

    /// Plays for as long as the view it animates is on screen.
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        var copy = self
        copy.repeatCount = nil
        copy.autoreverses = autoreverses
        return copy
    }

    // MARK: - Evaluation

    /// One play of the curve, in the curve's own seconds. Unknown for a
    /// custom curve, which says when it is over as it runs.
    var cycleDuration: Double {
        switch curve {
        case .timing(_, _, _, _, let duration): return duration
        case .spring(_, _, let settlingDuration): return settlingDuration
        case .custom: return .infinity
        }
    }

    /// Real seconds from start to finish, delay included — infinite for a
    /// repeat that never ends, or a custom curve.
    var totalDuration: Double {
        guard let repeatCount else { return .infinity }
        return delay + cycleDuration * Double(repeatCount) / speed
    }

    /// `elapsed` real seconds as the curve's own time: less the delay,
    /// times the speed.
    func localTime(_ elapsed: Double) -> Double {
        (elapsed - delay) * speed
    }

    /// The fraction of the change done `elapsed` real seconds in — 0 before
    /// it starts, 1 once it is over, and outside 0…1 for a spring that
    /// overshoots — and whether it is over. A built-in curve only: a custom
    /// one keeps state between frames and is driven by `AnimationRun`.
    func progress(after elapsed: Double) -> (fraction: Double, isFinished: Bool) {
        if case .custom = curve { return (1, true) }
        let time = localTime(elapsed)
        guard time > 0 else { return (0, false) }
        let cycle = cycleDuration
        guard cycle > 0 else { return (1, true) }
        let played = (time / cycle).rounded(.down)
        if let repeatCount, played >= Double(repeatCount) { return (1, true) }
        let local = time - played * cycle
        let fraction = curveValue(at: local)
        let backwards = autoreverses && played.truncatingRemainder(dividingBy: 2) == 1
        return (backwards ? 1 - fraction : fraction, false)
    }

    private func curveValue(at time: Double) -> Double {
        switch curve {
        case .timing(let x1, let y1, let x2, let y2, let duration):
            return UnitBezier(x1: x1, y1: y1, x2: x2, y2: y2).value(at: time / duration)
        case .spring(let spring, let initialVelocity, _):
            return spring.value(target: 1.0, initialVelocity: initialVelocity, time: time)
        case .custom:
            return 1
        }
    }
}

// MARK: - Bézier timing

/// A timing function through (0, 0), two control points and (1, 1): solve
/// x(t) = progress for t, then answer y(t). Newton's method with a
/// bisection fallback — WebKit's `UnitBezier`, in outline.
private struct UnitBezier {
    let cx, bx, ax: Double
    let cy, by, ay: Double

    init(x1: Double, y1: Double, x2: Double, y2: Double) {
        cx = 3 * x1
        bx = 3 * (x2 - x1) - cx
        ax = 1 - cx - bx
        cy = 3 * y1
        by = 3 * (y2 - y1) - cy
        ay = 1 - cy - by
    }

    func value(at x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        return sampleY(solveT(forX: x))
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    private func solveT(forX x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-7 { return t }
            let slope = slopeX(t)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        while low < high {
            let sample = sampleX(t)
            if abs(sample - x) < 1e-7 { return t }
            if x > sample { low = t } else { high = t }
            t = (low + high) / 2
            if high - low < 1e-7 { break }
        }
        return t
    }
}
