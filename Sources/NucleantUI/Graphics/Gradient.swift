//
//  Gradient.swift
//  NucleantUI
//

public struct Gradient: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public var color: Color
        public var location: Double

        public init(color: Color, location: Double) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// Evenly spaced stops, the common case.
    public init(colors: [Color]) {
        guard colors.count > 1 else {
            self.stops = colors.map { Stop(color: $0, location: 0) }
            return
        }
        let step = 1.0 / Double(colors.count - 1)
        self.stops = colors.enumerated().map { Stop(color: $1, location: Double($0) * step) }
    }
}

/// A named line style for strokes.
public struct StrokeStyle: Hashable, Sendable {
    public var lineWidth: Double
    public var lineCap: LineCap
    public var lineJoin: LineJoin
    public var dash: [Double]
    public var dashPhase: Double

    public init(
        lineWidth: Double = 1,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        dash: [Double] = [],
        dashPhase: Double = 0
    ) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

public enum LineCap: Hashable, Sendable {
    case butt, round, square
}

public enum LineJoin: Hashable, Sendable {
    case miter, round, bevel
}
