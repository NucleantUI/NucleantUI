//
//  Geometry.swift
//  NucleantUI
//
//  Doubles throughout. `Point` and `Size` are `SIMD2<Double>`, the vector
//  the render side (render nodes, Skia, ThorVG) already takes, so layout math
//  runs packed and hands over without repacking. `Rect` is SwiftUI's
//  origin + size.
//

/// A position: SwiftUI's `CGPoint`. `x`/`y`, `init(x:y:)`, `.zero` and the
/// arithmetic all come with `SIMD2`.
public typealias Point = SIMD2<Double>

/// An extent: SwiftUI's `CGSize`. `width`/`height` name the same two lanes as
/// `x`/`y`, so a size adds straight onto a point.
public typealias Size = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    public init(width: Double, height: Double) {
        self.init(width, height)
    }

    public var width: Double {
        get { x }
        set { x = newValue }
    }

    public var height: Double {
        get { y }
        set { y = newValue }
    }

    /// One axis of a point or size, so stack maths can be written once for
    /// both axes and read a size the same way it reads a `ProposedSize`.
    public subscript(axis: Axis) -> Double {
        get { axis == .horizontal ? x : y }
        set {
            if axis == .horizontal { x = newValue } else { y = newValue }
        }
    }

    /// `Swift.max(self, other)` in each lane, as one packed compare and
    /// select. The stdlib's `pointwiseMax` follows IEEE NaN rules lane by
    /// lane instead, which compiles to branchy scalar code.
    func lanewiseMax(_ other: Self) -> Self {
        replacing(with: other, where: other .>= self)
    }

    /// `Swift.min(self, other)` in each lane; see `lanewiseMax`.
    func lanewiseMin(_ other: Self) -> Self {
        replacing(with: other, where: other .< self)
    }
}

public struct Rect: Hashable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Point(x, y), size: Size(width, height))
    }

    public static let zero = Rect(origin: .zero, size: .zero)

    public var x: Double { origin.x }
    public var y: Double { origin.y }
    public var width: Double { size.width }
    public var height: Double { size.height }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }

    public var center: Point { origin + size / 2 }

    public func contains(_ point: Point) -> Bool {
        all((point .>= origin) .& (point .< origin + size))
    }

    public func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(origin: origin + Point(dx, dy), size: size)
    }

    public func insetBy(_ insets: EdgeInsets) -> Rect {
        let leadingTop = SIMD2(insets.leading, insets.top)
        let inner = size - leadingTop - SIMD2(insets.trailing, insets.bottom)
        return Rect(origin: origin + leadingTop, size: Size.zero.lanewiseMax(inner))
    }

    public func insetBy(_ amount: Double) -> Rect {
        insetBy(EdgeInsets(amount))
    }

    /// The intersection with `other`, or a zero-size rect at this origin when
    /// they don't overlap. Used for clipping a child into its parent.
    public func intersection(_ other: Rect) -> Rect {
        let lo = origin.lanewiseMax(other.origin)
        let hi = (origin + size).lanewiseMin(other.origin + other.size)
        guard all(hi .> lo) else { return Rect(origin: lo, size: .zero) }
        return Rect(origin: lo, size: hi - lo)
    }
}

public struct EdgeInsets: Hashable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ all: Double) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    public static let zero = EdgeInsets()

    public var horizontal: Double { leading + trailing }
    public var vertical: Double { top + bottom }

    public init(_ edges: Edge.Set, _ amount: Double) {
        self.init(
            top:      edges.contains(.top)      ? amount : 0,
            leading:  edges.contains(.leading)  ? amount : 0,
            bottom:   edges.contains(.bottom)   ? amount : 0,
            trailing: edges.contains(.trailing) ? amount : 0
        )
    }
}

public enum Edge: Int8, CaseIterable, Sendable {
    case top, leading, bottom, trailing

    public struct Set: OptionSet, Sendable {
        public var rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }

        public static let top      = Set(rawValue: 1 << 0)
        public static let leading  = Set(rawValue: 1 << 1)
        public static let bottom   = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)

        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical:   Set = [.top, .bottom]
        public static let all:        Set = [.top, .leading, .bottom, .trailing]
    }
}

/// The axis a stack lays out along. Named `Axis` to match SwiftUI.
public enum Axis: Hashable, Sendable {
    case horizontal
    case vertical

    public struct Set: OptionSet, Sendable {
        public var rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical   = Set(rawValue: 1 << 1)
    }

    /// The axis at right angles to this one.
    public var cross: Axis { self == .horizontal ? .vertical : .horizontal }
}

public struct Angle: Hashable, Sendable {
    public var radians: Double

    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { self.radians = degrees * .pi / 180 }

    public var degrees: Double { radians * 180 / .pi }

    public static let zero = Angle(radians: 0)
    public static func radians(_ value: Double) -> Angle { .init(radians: value) }
    public static func degrees(_ value: Double) -> Angle { .init(degrees: value) }
}

/// A point in a view's unit coordinate space — (0,0) top-leading to (1,1)
/// bottom-trailing. Gradients and effect anchors are expressed in it.
public struct UnitPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero         = UnitPoint(x: 0,   y: 0)
    public static let topLeading   = UnitPoint(x: 0,   y: 0)
    public static let top          = UnitPoint(x: 0.5, y: 0)
    public static let topTrailing  = UnitPoint(x: 1,   y: 0)
    public static let leading      = UnitPoint(x: 0,   y: 0.5)
    public static let center       = UnitPoint(x: 0.5, y: 0.5)
    public static let trailing     = UnitPoint(x: 1,   y: 0.5)
    public static let bottomLeading  = UnitPoint(x: 0,   y: 1)
    public static let bottom         = UnitPoint(x: 0.5, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1,   y: 1)

    /// This unit point resolved into `rect`.
    public func resolved(in rect: Rect) -> Point {
        rect.origin + rect.size * Point(x, y)
    }
}
