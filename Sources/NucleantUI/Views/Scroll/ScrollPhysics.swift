//
//  ScrollPhysics.swift
//  NucleantUI
//
//  How a scroll view moves on its own, one axis at a time, as closed forms
//  of the time: nothing is stepped, so a frame that comes late lands where
//  an on-time one would have.
//
//  * Past an edge under a finger, the content follows by less and less: the
//    rubber band, UIScrollView's `(1 - 1 / (x * 0.55 / d + 1)) * d`.
//  * Let go while moving, it slows down as UIScrollView's normal rate does:
//    the speed falls by 0.2% each millisecond, so it travels
//    `v / (-1000 ln 0.998)` more, about half its speed in points.
//  * Reaching an edge while it slows (or let go past one), a spring brings
//    it back to the edge, critically damped: over the edge by as much as the
//    speed it arrived with carries it, and back without swinging.
//  * Given a place to stop (a scroll target behavior, a programmatic
//    scroll), the same spring takes it there from where it is, as fast as
//    it is going.
//

import Foundation

/// The numbers the motions are made of.
enum ScrollPhysics {
    /// UIScrollView's `.normal` deceleration rate: the speed kept each
    /// millisecond.
    static let decelerationRate = 0.998

    /// How fast the speed decays, per second: `v(t) = v₀·e^(-k·t)`.
    static let decay = -1000 * log(decelerationRate)

    /// How much of the way past an edge the content follows a finger — the
    /// rubber band's stiffness. UIScrollView's constant.
    static let rubberBandCoefficient = 0.55

    /// The angular frequency of the spring that settles the content on an
    /// edge or a target: 99.5% of the way in about 0.6 s.
    static let settlingFrequency = 12.3

    /// Faster than this, speed carried over an edge is cut down, so a hard
    /// fling bounces about as far as a quick one.
    static let maximumBounceSpeed = 4000.0

    /// The fastest a finger lets go of the content, in points per second:
    /// events that arrive together, or a clock that stalls, make no fling
    /// faster than a hard one by hand.
    static let maximumReleaseSpeed = 8000.0

    /// Slower than this, in points per second, the content has stopped.
    static let restingSpeed = 0.5

    /// Closer than this to where it is going, in points, it has arrived.
    static let restingDistance = 0.25

    /// How far the content shows for `overshoot` points dragged past an
    /// edge, in a viewport `dimension` long.
    static func rubberBand(_ overshoot: Double, dimension: Double) -> Double {
        guard dimension > 0 else { return 0 }
        let magnitude = abs(overshoot)
        let shown = (1 - 1 / (magnitude * rubberBandCoefficient / dimension + 1)) * dimension
        return overshoot < 0 ? -shown : shown
    }

    /// How far a finger must have dragged past an edge for the content to
    /// show `shown` points past it — the rubber band undone, for a press
    /// that catches the content while it bounces.
    static func dragDistance(showing shown: Double, dimension: Double) -> Double {
        guard dimension > 0 else { return 0 }
        let magnitude = min(abs(shown), dimension * 0.999)
        let dragged = (dimension / rubberBandCoefficient) * (1 / (1 - magnitude / dimension) - 1)
        return shown < 0 ? -dragged : dragged
    }

    /// Where content let go of at `position`, moving at `velocity`, comes to
    /// rest with nothing in its way.
    static func projectedEnd(from position: Double, velocity: Double) -> Double {
        position + velocity / decay
    }
}

/// One axis of a scroll view moving on its own, since `start`.
struct ScrollAxisMotion: Equatable {
    enum Kind: Equatable {
        /// Slowing down freely from `position` at `velocity`.
        case decelerating(position: Double, velocity: Double)
        /// Springing from `position`, moving at `velocity`, to `target`, at
        /// angular frequency `frequency`.
        case settling(position: Double, velocity: Double, target: Double, frequency: Double)
    }

    private(set) var kind: Kind
    /// When the current kind of motion began, in seconds on the frame clock.
    private(set) var start: Double

    /// Whether it may run past the edges and come back. Without, it stops
    /// dead at the edge it reaches.
    let bounces: Bool

    init(_ kind: Kind, at start: Double, bounces: Bool) {
        self.kind = kind
        self.start = start
        self.bounces = bounces
    }

    /// Let go at `position` moving at `velocity`, with the content able to
    /// rest anywhere in `bounds`: slowing down, or — let go past an edge,
    /// and not about to come back in on its own — springing back to it.
    static func released(
        at position: Double,
        velocity: Double,
        bounds: ClosedRange<Double>,
        time: Double,
        bounces: Bool
    ) -> ScrollAxisMotion? {
        if !bounds.contains(position) {
            let edge = position < bounds.lowerBound ? bounds.lowerBound : bounds.upperBound
            let end = ScrollPhysics.projectedEnd(from: position, velocity: velocity)
            // Flung back in hard enough to come to rest inside: it slows
            // down through the edge rather than springing at it.
            let comesBackIn = (edge == bounds.lowerBound && end > edge) || (edge == bounds.upperBound && end < edge)
            if comesBackIn {
                return ScrollAxisMotion(.decelerating(position: position, velocity: velocity), at: time, bounces: bounces)
            }
            return ScrollAxisMotion(
                .settling(position: position, velocity: velocity, target: edge, frequency: ScrollPhysics.settlingFrequency),
                at: time, bounces: bounces
            )
        }
        guard abs(velocity) > ScrollPhysics.restingSpeed else { return nil }
        return ScrollAxisMotion(.decelerating(position: position, velocity: velocity), at: time, bounces: bounces)
    }

    /// From `position` at `velocity` to rest on `target`: the settling
    /// spring, made stiffer when needed so that it does not run past it.
    static func settling(
        from position: Double,
        velocity: Double,
        to target: Double,
        time: Double,
        bounces: Bool
    ) -> ScrollAxisMotion? {
        let away = position - target
        if abs(away) < ScrollPhysics.restingDistance, abs(velocity) < ScrollPhysics.restingSpeed { return nil }
        var frequency = ScrollPhysics.settlingFrequency
        // Heading for the target faster than the spring would slow it:
        // `velocity + frequency * away` keeps the sign of `away` only from
        // this frequency up.
        if away != 0, velocity * away < 0 {
            frequency = max(frequency, abs(velocity / away))
        }
        return ScrollAxisMotion(
            .settling(position: position, velocity: velocity, target: target, frequency: frequency),
            at: time, bounces: bounces
        )
    }

    /// Where it is and how fast it is going at `time`, and whether it has
    /// stopped — moving on to the spring when it slows into an edge.
    mutating func sample(at time: Double, bounds: ClosedRange<Double>) -> (position: Double, velocity: Double, isFinished: Bool) {
        let elapsed = max(0, time - start)
        switch kind {
        case .decelerating(let position, let velocity):
            let k = ScrollPhysics.decay
            let fade = exp(-k * elapsed)
            var now = position + velocity * (1 - fade) / k
            var speed = velocity * fade
            // An edge it runs into, when it started on the near side of it.
            if let edge = edgeCrossed(from: position, to: now, bounds: bounds) {
                // When it got there: `1 - e^(-k t) = (edge - p₀) k / v₀`.
                let fraction = 1 - (edge - position) * k / velocity
                let reached = fraction > 0 ? start - log(fraction) / k : time
                let arriving = velocity * exp(-k * max(0, reached - start))
                guard bounces else {
                    kind = .decelerating(position: edge, velocity: 0)
                    return (edge, 0, true)
                }
                let carried = max(-ScrollPhysics.maximumBounceSpeed, min(ScrollPhysics.maximumBounceSpeed, arriving))
                kind = .settling(position: edge, velocity: carried, target: edge, frequency: ScrollPhysics.settlingFrequency)
                start = min(reached, time)
                return sample(at: time, bounds: bounds)
            }
            if abs(speed) < ScrollPhysics.restingSpeed {
                now = ScrollPhysics.projectedEnd(from: position, velocity: velocity)
                speed = 0
                return (now, 0, true)
            }
            return (now, speed, false)

        case .settling(let position, let velocity, let target, let frequency):
            // x(t) − T = (A + B t) e^(−ω t), A = x₀ − T, B = v₀ + ω A.
            let a = position - target
            let b = velocity + frequency * a
            let fade = exp(-frequency * elapsed)
            let away = (a + b * elapsed) * fade
            let speed = (b - frequency * (a + b * elapsed)) * fade
            if abs(away) < ScrollPhysics.restingDistance, abs(speed) < ScrollPhysics.restingSpeed * 10 {
                return (target, 0, true)
            }
            return (target + away, speed, false)
        }
    }

    /// The edge of `bounds` that the move from `from` to `to` runs over,
    /// coming from inside them (or from on the edge).
    private func edgeCrossed(from: Double, to: Double, bounds: ClosedRange<Double>) -> Double? {
        if from <= bounds.upperBound, to > bounds.upperBound { return bounds.upperBound }
        if from >= bounds.lowerBound, to < bounds.lowerBound { return bounds.lowerBound }
        return nil
    }
}

/// How fast a finger was moving the content when it lifted, from where it
/// put the content in the last tenth of a second. A finger that held still
/// for a moment before lifting flings nothing; moves too close together in
/// time to tell a speed from fling nothing either.
struct ScrollVelocityTracker {
    /// Moves older than this, before the newest, do not count.
    static let horizon = 0.1
    /// Still for longer than this when it lifts, the finger had stopped.
    static let stillness = 0.04
    /// The moves counted must span at least this long.
    static let minimumSpan = 0.008

    private var samples: [(offset: Point, time: Double)] = []

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// The content was at `offset` at `time`.
    mutating func add(_ offset: Point, at time: Double) {
        if let last = samples.last, time < last.time { return }
        samples.append((offset, time))
        // Keep the newest and what lies within the horizon of it.
        if let newest = samples.last?.time {
            while samples.count > 2, newest - samples[0].time > Self.horizon {
                samples.removeFirst()
            }
        }
    }

    /// The content's speed, in points per second, for a finger lifting at
    /// `time`.
    func velocity(at time: Double) -> Point {
        guard let last = samples.last, time - last.time <= Self.stillness else { return .zero }
        guard let first = samples.first(where: { last.time - $0.time <= Self.horizon }) else { return .zero }
        let span = last.time - first.time
        guard span >= Self.minimumSpan else { return .zero }
        return (last.offset - first.offset) / span
    }
}
