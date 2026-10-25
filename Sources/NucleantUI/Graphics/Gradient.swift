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

/// How a shape is painted. `ShapeStyle` in SwiftUI is a protocol; here it is a
/// closed enum because the renderer has to switch on it to build the matching
/// `Tvg_Gradient`, and the set of fills ThorVG offers is itself closed.
///
/// Light and dark appearance live here, not in `Color`: a `.dynamic` style —
/// and the semantic ones built from it, `.primary`, `.background`, … — is
/// resolved against the color scheme in effect where it is drawn.
public enum ShapeStyle: Hashable, Sendable {
    case color(Color)
    /// One color in light mode and another in dark.
    case dynamic(light: Color, dark: Color)
    case linearGradient(Gradient, startPoint: UnitPoint, endPoint: UnitPoint)
    case radialGradient(Gradient, center: UnitPoint, startRadius: Double, endRadius: Double)

    /// This style as drawn under `scheme`: a dynamic one becomes the color
    /// it shows there, anything else is itself.
    public func resolved(for scheme: ColorScheme) -> ShapeStyle {
        guard case .dynamic(let light, let dark) = self else { return self }
        return .color(scheme == .dark ? dark : light)
    }

    /// A representative flat color — used where a gradient can't be applied
    /// (text outlines, 1px borders). A dynamic style gives its light color;
    /// resolve it first for the scheme it is drawn under.
    public var flatColor: Color {
        switch self {
        case .color(let color), .dynamic(let color, _):
            return color
        case .linearGradient(let gradient, _, _), .radialGradient(let gradient, _, _, _):
            return gradient.stops.first?.color ?? .clear
        }
    }

    public var isClear: Bool {
        switch self {
        case .color(let color): return color.isClear
        case .dynamic(let light, let dark): return light.isClear && dark.isClear
        case .linearGradient, .radialGradient: return false
        }
    }

    /// Every color in the style faded by `value`.
    public func opacity(_ value: Double) -> ShapeStyle {
        switch self {
        case .color(let color):
            return .color(color.opacity(value))
        case .dynamic(let light, let dark):
            return .dynamic(light: light.opacity(value), dark: dark.opacity(value))
        case .linearGradient(let gradient, let start, let end):
            return .linearGradient(gradient.opacity(value), startPoint: start, endPoint: end)
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            return .radialGradient(gradient.opacity(value), center: center, startRadius: startRadius, endRadius: endRadius)
        }
    }
}

extension Gradient {
    fileprivate func opacity(_ value: Double) -> Gradient {
        Gradient(stops: stops.map { Stop(color: $0.color.opacity(value), location: $0.location) })
    }
}

extension ShapeStyle {
    // MARK: Semantic styles
    //
    // Dynamic: each has a light and a dark appearance, resolved where it is
    // drawn. Values follow the system palettes — near-black text on
    // near-white in light mode, the reverse in dark — so an app that only
    // uses these reads correctly under either.

    /// Default text/foreground color.
    public static let primary = ShapeStyle.dynamic(light: Color(white: 0.1), dark: Color(white: 0.95))
    /// Captions, secondary labels.
    public static let secondary = ShapeStyle.dynamic(light: Color(white: 0.45), dark: Color(white: 0.65))
    /// Placeholders, disabled text.
    public static let tertiary = ShapeStyle.dynamic(light: Color(white: 0.65), dark: Color(white: 0.45))
    /// The window background. The dark value matches the engine's own
    /// clear color; the window sets the clear color to whichever applies.
    public static let background = ShapeStyle.dynamic(light: Color(hex: 0xF2F2F7), dark: Color(red: 0.02, green: 0.02, blue: 0.04))
    /// Panels and cards over the background.
    public static let secondaryBackground = ShapeStyle.dynamic(light: Color.white, dark: Color(hex: 0x1C1F26))
    /// Rows and controls over a panel.
    public static let tertiaryBackground = ShapeStyle.dynamic(light: Color(hex: 0xE9E9EE), dark: Color(hex: 0x272B34))
    /// Hairlines between things.
    public static let separator = ShapeStyle.dynamic(light: Color(white: 0, opacity: 0.12), dark: Color(white: 1, opacity: 0.10))
    /// A control's track or well — a fader's groove, a bar's empty part.
    public static let fill = ShapeStyle.dynamic(light: Color(white: 0, opacity: 0.08), dark: Color(white: 1, opacity: 0.08))
}

extension ShapeStyle {
    public static func linearGradient(
        colors: [Color],
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) -> ShapeStyle {
        .linearGradient(Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
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
