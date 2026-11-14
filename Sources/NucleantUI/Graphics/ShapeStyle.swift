//
//  ShapeStyle.swift
//  NucleantUI
//
//  How a shape, a text or a background is painted: a color, a gradient, a
//  style that depends on where it is drawn — the foreground in effect, the
//  tint, light or dark.
//
//  Each style is a type of its own, and the modifiers that take one are
//  generic over it, so where a style is known its type is known. A style is
//  resolved against the environment of the view it paints when that view is
//  built, into the paint the renderer draws (`_ResolvedPaint`): a flat color
//  or a gradient. What it read to resolve — the color scheme, the foreground
//  style — is read like any other environment value, so a change to it
//  rebuilds exactly the views that resolved a style from it.
//

/// A color or pattern to paint with.
///
/// The framework's styles — `Color`, the gradients, `.primary`,
/// `.background`, `.tint`, … — are drawn as they are. A style of an app's
/// own resolves to one of them, given the environment it is drawn in:
///
/// ```swift
/// struct Warning: ShapeStyle {
///     func resolve(in environment: EnvironmentValues) -> Color {
///         environment.colorScheme == .dark ? .orange : .red
///     }
/// }
/// ```
public protocol ShapeStyle: Sendable {
    /// The style this one is drawn as.
    associatedtype Resolved: ShapeStyle = Never

    /// This style in `environment`, as a style the framework draws.
    func resolve(in environment: EnvironmentValues) -> Resolved

    /// What the renderer draws for this style in `environment`. The
    /// framework's own styles answer it themselves; any other style is what
    /// `resolve(in:)` makes of it.
    func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint
}

extension ShapeStyle {
    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        resolve(in: environment)._resolvedPaint(in: environment)
    }
}

extension ShapeStyle where Resolved == Never {
    /// A style the framework draws as it is resolves to nothing else.
    public func resolve(in environment: EnvironmentValues) -> Never {
        preconditionFailure("\(Self.self) is drawn as it is; it does not resolve to another style")
    }
}

extension Never: ShapeStyle {
    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        switch self {}
    }
}

// MARK: - What the renderer draws

/// A style as the renderer draws it: one flat color, or a gradient of
/// colors laid out in the painted shape's bounds. Public only because
/// `ShapeStyle`'s requirement hands it back; what it holds is the
/// framework's. The set is closed because the renderer's is.
public struct _ResolvedPaint: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case color(Color)
        case linearGradient(Gradient, startPoint: UnitPoint, endPoint: UnitPoint)
        case radialGradient(Gradient, center: UnitPoint, startRadius: Double, endRadius: Double)
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    static func color(_ color: Color) -> _ResolvedPaint {
        _ResolvedPaint(.color(color))
    }

    /// A representative flat color — for what a gradient can't be applied
    /// to (a text, a 1px border): a gradient's first stop.
    var flatColor: Color {
        switch kind {
        case .color(let color):
            return color
        case .linearGradient(let gradient, _, _), .radialGradient(let gradient, _, _, _):
            return gradient.stops.first?.color ?? .clear
        }
    }

    /// Paints nothing: a clear color. A gradient always paints.
    var isClear: Bool {
        if case .color(let color) = kind { return color.isClear }
        return false
    }

    /// Every color faded by `value`; at full opacity, the paint as it is.
    func opacity(_ value: Double) -> _ResolvedPaint {
        guard value < 1 else { return self }
        switch kind {
        case .color(let color):
            return .color(color.opacity(value))
        case .linearGradient(let gradient, let start, let end):
            return _ResolvedPaint(.linearGradient(gradient.opacity(value), startPoint: start, endPoint: end))
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            return _ResolvedPaint(.radialGradient(
                gradient.opacity(value), center: center, startRadius: startRadius, endRadius: endRadius
            ))
        }
    }
}

extension Gradient {
    func opacity(_ value: Double) -> Gradient {
        Gradient(stops: stops.map { Stop(color: $0.color.opacity(value), location: $0.location) })
    }
}

extension ShapeStyle {
    /// What this style paints in `environment`.
    func paint(in environment: EnvironmentValues) -> _ResolvedPaint {
        _resolvedPaint(in: environment)
    }
}

// MARK: - Color

extension Color: ShapeStyle {
    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        .color(self)
    }
}

extension ShapeStyle where Self == Color {
    public static var clear: Color { Color.clear }
    public static var black: Color { Color.black }
    public static var white: Color { Color.white }
    public static var gray: Color { Color.gray }
    public static var red: Color { Color.red }
    public static var orange: Color { Color.orange }
    public static var yellow: Color { Color.yellow }
    public static var green: Color { Color.green }
    public static var mint: Color { Color.mint }
    public static var teal: Color { Color.teal }
    public static var cyan: Color { Color.cyan }
    public static var blue: Color { Color.blue }
    public static var indigo: Color { Color.indigo }
    public static var purple: Color { Color.purple }
    public static var pink: Color { Color.pink }
    public static var brown: Color { Color.brown }
}

// MARK: - Light and dark

/// One color in light mode and another in dark — NucleantUI's own style for
/// a color of an app's palette that follows the appearance. The semantic
/// styles (`.primary`, `.background`, `.separator`, …) are built from the
/// same pairs.
public struct DynamicShapeStyle: ShapeStyle, Hashable {
    public var light: Color
    public var dark: Color

    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    /// The color shown under `scheme`.
    public func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        .color(color(for: environment.colorScheme))
    }
}

extension ShapeStyle where Self == DynamicShapeStyle {
    /// One color in light mode and another in dark.
    public static func dynamic(light: Color, dark: Color) -> DynamicShapeStyle {
        DynamicShapeStyle(light: light, dark: dark)
    }
}

// MARK: - Semantic styles
//
// Each has a light and a dark appearance. Values follow the system
// palettes — near-black text on near-white in light mode, the reverse in
// dark — so an app that only uses these reads correctly under either.

/// The levels of foreground content: `.primary` for text, `.secondary` for
/// captions and secondary labels, `.tertiary` for placeholders and disabled
/// text.
public struct HierarchicalShapeStyle: ShapeStyle, Hashable {
    let level: UInt8

    public static let primary = HierarchicalShapeStyle(level: 0)
    public static let secondary = HierarchicalShapeStyle(level: 1)
    public static let tertiary = HierarchicalShapeStyle(level: 2)

    private static let colors = [
        DynamicShapeStyle(light: Color(white: 0.1), dark: Color(white: 0.95)),
        DynamicShapeStyle(light: Color(white: 0.45), dark: Color(white: 0.65)),
        DynamicShapeStyle(light: Color(white: 0.65), dark: Color(white: 0.45)),
    ]

    /// The pair this level is drawn with.
    var colors: DynamicShapeStyle { Self.colors[Int(level)] }

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        colors._resolvedPaint(in: environment)
    }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    /// Default text and foreground color.
    public static var primary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 0) }
    /// Captions, secondary labels.
    public static var secondary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 1) }
    /// Placeholders, disabled text.
    public static var tertiary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 2) }
}

/// The backgrounds content sits on: the window's (`.background`), a panel or
/// card over it (`.secondaryBackground`), a row or control over a panel
/// (`.tertiaryBackground`).
public struct BackgroundStyle: ShapeStyle, Hashable {
    let level: UInt8

    public init() {
        self.level = 0
    }

    init(level: UInt8) {
        self.level = level
    }

    private static let colors = [
        // The dark value matches the engine's own clear color; the window
        // sets the clear color to whichever applies.
        DynamicShapeStyle(light: Color(hex: 0xF2F2F7), dark: Color(red: 0.02, green: 0.02, blue: 0.04)),
        DynamicShapeStyle(light: Color.white, dark: Color(hex: 0x1C1F26)),
        DynamicShapeStyle(light: Color(hex: 0xE9E9EE), dark: Color(hex: 0x272B34)),
    ]

    /// The pair this level is drawn with.
    var colors: DynamicShapeStyle { Self.colors[Int(level)] }

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        colors._resolvedPaint(in: environment)
    }
}

extension ShapeStyle where Self == BackgroundStyle {
    /// The window background.
    public static var background: BackgroundStyle { BackgroundStyle() }
    /// Panels and cards over the background.
    public static var secondaryBackground: BackgroundStyle { BackgroundStyle(level: 1) }
    /// Rows and controls over a panel.
    public static var tertiaryBackground: BackgroundStyle { BackgroundStyle(level: 2) }
}

/// Hairlines between things.
public struct SeparatorShapeStyle: ShapeStyle, Hashable {
    public init() {}

    static let colors = DynamicShapeStyle(light: Color(white: 0, opacity: 0.12), dark: Color(white: 1, opacity: 0.10))

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        Self.colors._resolvedPaint(in: environment)
    }
}

extension ShapeStyle where Self == SeparatorShapeStyle {
    /// Hairlines between things.
    public static var separator: SeparatorShapeStyle { SeparatorShapeStyle() }
}

/// A control's track or well — a fader's groove, a bar's empty part.
public struct FillShapeStyle: ShapeStyle, Hashable {
    public init() {}

    static let colors = DynamicShapeStyle(light: Color(white: 0, opacity: 0.08), dark: Color(white: 1, opacity: 0.08))

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        Self.colors._resolvedPaint(in: environment)
    }
}

extension ShapeStyle where Self == FillShapeStyle {
    /// A control's track or well.
    public static var fill: FillShapeStyle { FillShapeStyle() }
}

// MARK: - Styles from the environment

/// The foreground style in effect where it is drawn — what `.foregroundStyle`
/// set above, `.primary` where nothing did.
public struct ForegroundStyle: ShapeStyle, Hashable {
    public init() {}

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        // `.foregroundStyle(.foreground)` names itself: what it stands for
        // is the default, not itself again.
        guard !Self.isResolving else { return HierarchicalShapeStyle(level: 0)._resolvedPaint(in: environment) }
        Self.isResolving = true
        defer { Self.isResolving = false }
        return environment.foregroundStyle._resolvedPaint(in: environment)
    }

    nonisolated(unsafe) private static var isResolving = false
}

extension ShapeStyle where Self == ForegroundStyle {
    /// The foreground style in effect.
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

/// The tint in effect where it is drawn — what `.tint` set above, blue where
/// nothing did.
public struct TintShapeStyle: ShapeStyle, Hashable {
    public init() {}

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        // `.tint(.tint)` names itself, as `.foreground` can.
        guard !Self.isResolving else { return .color(.blue) }
        Self.isResolving = true
        defer { Self.isResolving = false }
        return environment.tint._resolvedPaint(in: environment)
    }

    nonisolated(unsafe) private static var isResolving = false
}

extension ShapeStyle where Self == TintShapeStyle {
    /// The tint in effect.
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

// MARK: - Gradients

/// Colors along a line, from `startPoint` to `endPoint` of the painted
/// shape's bounds.
public struct LinearGradient: ShapeStyle, Hashable {
    public var gradient: Gradient
    public var startPoint: UnitPoint
    public var endPoint: UnitPoint

    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        _ResolvedPaint(.linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
    }
}

extension ShapeStyle where Self == LinearGradient {
    public static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }

    /// Evenly spaced colors, top to bottom unless told otherwise.
    public static func linearGradient(
        colors: [Color],
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }

    public static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}

/// Colors in rings around `center` of the painted shape's bounds, from
/// `startRadius` to `endRadius`.
public struct RadialGradient: ShapeStyle, Hashable {
    public var gradient: Gradient
    public var center: UnitPoint
    public var startRadius: Double
    public var endRadius: Double

    public init(gradient: Gradient, center: UnitPoint, startRadius: Double, endRadius: Double) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    public init(colors: [Color], center: UnitPoint, startRadius: Double, endRadius: Double) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius)
    }

    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: Double, endRadius: Double) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius)
    }

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        _ResolvedPaint(.radialGradient(gradient, center: center, startRadius: startRadius, endRadius: endRadius))
    }
}

extension ShapeStyle where Self == RadialGradient {
    public static func radialGradient(
        _ gradient: Gradient, center: UnitPoint, startRadius: Double, endRadius: Double
    ) -> RadialGradient {
        RadialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }

    public static func radialGradient(
        colors: [Color], center: UnitPoint, startRadius: Double, endRadius: Double
    ) -> RadialGradient {
        RadialGradient(colors: colors, center: center, startRadius: startRadius, endRadius: endRadius)
    }

    public static func radialGradient(
        stops: [Gradient.Stop], center: UnitPoint, startRadius: Double, endRadius: Double
    ) -> RadialGradient {
        RadialGradient(stops: stops, center: center, startRadius: startRadius, endRadius: endRadius)
    }
}

// MARK: - Opacity

/// A style with its colors faded.
public struct _OpacityShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let style: Base
    let opacity: Float

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        style._resolvedPaint(in: environment).opacity(Double(opacity))
    }
}

extension _OpacityShapeStyle: Equatable where Base: Equatable {}
extension _OpacityShapeStyle: Hashable where Base: Hashable {}

extension _OpacityShapeStyle: ViewInput {
    public func _isEquivalent(to other: _OpacityShapeStyle<Base>) -> Bool {
        opacity == other.opacity && _areEquivalent(style, other.style)
    }
}

extension ShapeStyle {
    /// This style with every color faded by `opacity`.
    public func opacity(_ opacity: Double) -> some ShapeStyle {
        _OpacityShapeStyle(style: self, opacity: Float(opacity))
    }
}

// MARK: - Erased

/// Any style, as one type — for a value whose style changes from one use to
/// the next: two branches of a condition, the environment's foreground
/// style and tint.
public struct AnyShapeStyle: ShapeStyle {
    let box: AnyShapeStyleBox

    public init<S: ShapeStyle>(_ style: S) {
        if let erased = style as? AnyShapeStyle {
            self.box = erased.box
        } else {
            self.box = ShapeStyleBox(style)
        }
    }

    public func _resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        box.resolvedPaint(in: environment)
    }
}

extension AnyShapeStyle: ViewInput {
    /// Holding a style of the same type, equivalent as that type's are.
    public func _isEquivalent(to other: AnyShapeStyle) -> Bool {
        box === other.box || box.isEquivalent(to: other.box)
    }
}

/// The style an `AnyShapeStyle` holds; `ShapeStyleBox` holds it as its type.
class AnyShapeStyleBox: @unchecked Sendable {
    func resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        fatalError("ShapeStyleBox overrides it")
    }

    @MainActor
    func isEquivalent(to other: AnyShapeStyleBox) -> Bool {
        fatalError("ShapeStyleBox overrides it")
    }
}

final class ShapeStyleBox<S: ShapeStyle>: AnyShapeStyleBox, @unchecked Sendable {
    let style: S

    init(_ style: S) {
        self.style = style
    }

    override func resolvedPaint(in environment: EnvironmentValues) -> _ResolvedPaint {
        style._resolvedPaint(in: environment)
    }

    @MainActor
    override func isEquivalent(to other: AnyShapeStyleBox) -> Bool {
        guard let other = other as? ShapeStyleBox<S> else { return false }
        return _areEquivalent(style, other.style)
    }
}
