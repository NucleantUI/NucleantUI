//
//  UnitCurve.swift
//  NucleantUI
//

import Foundation

/// A function defined by a two-dimensional curve that maps an input
/// progress in the range [0,1] to an output progress that is also in the
/// range [0,1]. By changing the shape of the curve, the effective speed
/// of an animation or other interpolation can be changed.
///
/// The horizontal (x) axis defines the input progress: a single input
/// progress value in the range [0,1] must be provided when evaluating a
/// curve.
///
/// The vertical (y) axis maps to the output progress: when a curve is
/// evaluated, the y component of the point that intersects the input progress
/// is returned.
public struct UnitCurve: Hashable, Sendable {

    enum Kind: Hashable, Sendable {
        case linear
        /// A cubic Bézier from (0, 0) to (1, 1) through two control points.
        case bezier(x1: Double, y1: Double, x2: Double, y2: Double)
        case circularEaseIn
        case circularEaseOut
        case circularEaseInOut
        /// Another curve with its axes swapped.
        indirect case inverse(Kind)
    }

    let kind: Kind

    /// Creates a new curve using bezier control points.
    ///
    /// The x components of the control points are clamped to the range [0,1] when
    /// the curve is evaluated.
    ///
    /// - Parameters:
    ///   - startControlPoint: The cubic Bézier control point associated with
    ///     the curve's start point at (0, 0). The tangent vector from the
    ///     start point to its control point defines the initial velocity of
    ///     the timing function.
    ///   - endControlPoint: The cubic Bézier control point associated with the
    ///     curve's end point at (1, 1). The tangent vector from the end point
    ///     to its control point defines the final velocity of the timing
    ///     function.
    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(kind: .bezier(
            x1: min(max(startControlPoint.x, 0), 1), y1: startControlPoint.y,
            x2: min(max(endControlPoint.x, 0), 1), y2: endControlPoint.y
        ))
    }

    /// A linear curve.
    public static let linear = UnitCurve(kind: .linear)

    /// A bezier curve that starts out slowly, speeds up over the middle,
    /// then slows down again as it approaches the end.
    public static let easeInOut = UnitCurve(kind: .bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1))

    /// A bezier curve that starts out slowly, then speeds up as it finishes.
    public static let easeIn = UnitCurve(kind: .bezier(x1: 0.42, y1: 0, x2: 1, y2: 1))

    /// A bezier curve that starts out quickly, then slows down as it
    /// approaches the end.
    public static let easeOut = UnitCurve(kind: .bezier(x1: 0, y1: 0, x2: 0.58, y2: 1))

    /// A curve that starts out slowly, then speeds up as it finishes.
    ///
    /// The shape of the curve is equal to the fourth (bottom right) quadrant
    /// of a unit circle.
    public static let circularEaseIn = UnitCurve(kind: .circularEaseIn)

    /// A circular curve that starts out quickly, then slows down as it
    /// approaches the end.
    ///
    /// The shape of the curve is equal to the second (top left) quadrant of
    /// a unit circle.
    public static let circularEaseOut = UnitCurve(kind: .circularEaseOut)

    /// A circular curve that starts out slowly, speeds up over the middle,
    /// then slows down again as it approaches the end.
    ///
    /// The shape of the curve is defined by a piecewise combination of
    /// `circularEaseIn` and `circularEaseOut`.
    public static let circularEaseInOut = UnitCurve(kind: .circularEaseInOut)

    /// Returns the output value (y component) of the curve at the given time.
    ///
    /// - Parameters:
    ///   - time: The input progress (x component). The provided value is
    ///     clamped to the range [0,1].
    ///
    /// - Returns: The output value (y component) of the curve at the given
    ///   progress.
    public func value(at progress: Double) -> Double {
        Self.value(of: kind, at: min(max(progress, 0), 1))
    }

    /// Returns the rate of change (first derivative) of the output value of
    /// the curve at the given time.
    ///
    /// - Parameters:
    ///   - progress: The input progress (x component). The provided value is
    ///     clamped to the range [0,1].
    ///
    /// - Returns: The velocity of the output value (y component) of the curve
    ///   at the given time.
    public func velocity(at progress: Double) -> Double {
        let x = min(max(progress, 0), 1)
        let step = 1e-4
        let lower = max(0, x - step), upper = min(1, x + step)
        return (Self.value(of: kind, at: upper) - Self.value(of: kind, at: lower)) / (upper - lower)
    }

    /// Returns a copy of the curve with its x and y components swapped.
    ///
    /// The inverse can be used to solve a curve in reverse: given a
    /// known output (y) value, the corresponding input (x) value can be found
    /// by using `inverse`:
    ///
    ///     let curve = UnitCurve.easeInOut
    ///
    ///     /// The input time for which an easeInOut curve returns 0.6.
    ///     let inputTime = curve.inverse.value(at: 0.6)
    public var inverse: UnitCurve {
        switch kind {
        case .linear: return self
        case .bezier(let x1, let y1, let x2, let y2): return UnitCurve(kind: .bezier(x1: y1, y1: x1, x2: y2, y2: x2))
        case .circularEaseIn: return .circularEaseOut
        case .circularEaseOut: return .circularEaseIn
        case .inverse(let inner): return UnitCurve(kind: inner)
        case .circularEaseInOut: return UnitCurve(kind: .inverse(kind))
        }
    }

    private static func value(of kind: Kind, at x: Double) -> Double {
        switch kind {
        case .linear:
            return x
        case .bezier(let x1, let y1, let x2, let y2):
            let t = parameter(atX: x, x1: x1, x2: x2)
            return cubic(t, y1, y2)
        case .circularEaseIn:
            return 1 - (1 - x * x).squareRoot()
        case .circularEaseOut:
            return (1 - (x - 1) * (x - 1)).squareRoot()
        case .circularEaseInOut:
            if x < 0.5 { return (1 - (1 - 4 * x * x).squareRoot()) / 2 }
            return ((1 - (-2 * x + 2) * (-2 * x + 2)).squareRoot() + 1) / 2
        case .inverse(let inner):
            // The x at which the curve reaches `x`: the curves are
            // increasing, so halving finds it.
            var low = 0.0, high = 1.0
            for _ in 0..<50 {
                let middle = (low + high) / 2
                if value(of: inner, at: middle) < x { low = middle } else { high = middle }
            }
            return (low + high) / 2
        }
    }

    /// One coordinate of a cubic Bézier from 0 to 1 through `p1` and `p2`.
    private static func cubic(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    /// The curve parameter at which the x coordinate is `x`: Newton's
    /// method, halving where it does not converge.
    private static func parameter(atX x: Double, x1: Double, x2: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = cubic(t, x1, x2) - x
            if abs(error) < 1e-7 { return t }
            let u = 1 - t
            let slope = 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
            guard abs(slope) > 1e-6 else { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<50 {
            let value = cubic(t, x1, x2)
            if abs(value - x) < 1e-7 { return t }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return t
    }
}
