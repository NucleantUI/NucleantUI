//
//  EnvironmentModifiers.swift
//  NucleantUI
//

extension View {

    /// Sets one environment value for this view and everything inside it.
    public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> some View {
        _ModifierView(content: self, modifier: EnvironmentKeyPathModifier(keyPath: keyPath, value: value))
    }

    /// Fixes the appearance for this view and everything inside it,
    /// whatever the system is set to.
    public func colorScheme(_ scheme: ColorScheme) -> some View {
        _ModifierView(content: self, modifier: ColorSchemeModifier(scheme: scheme))
    }

    public func font(_ font: Font) -> some View {
        _ModifierView(content: self, modifier: FontModifier(font: font))
    }

    public func foregroundColor(_ color: Color) -> some View {
        _ModifierView(content: self, modifier: ForegroundColorModifier(color: color))
    }

    /// The foreground for text and shapes below — a semantic style such as
    /// `.secondary`, a light/dark pair, a gradient.
    public func foregroundStyle(_ style: ShapeStyle) -> some View {
        _ModifierView(content: self, modifier: ForegroundStyleModifier(style: style))
    }

    public func foregroundStyle(_ color: Color) -> some View {
        _ModifierView(content: self, modifier: ForegroundStyleColorModifier(color: color))
    }

    public func tint(_ color: Color) -> some View {
        _ModifierView(content: self, modifier: TintColorModifier(color: color))
    }

    public func tint(_ style: ShapeStyle) -> some View {
        _ModifierView(content: self, modifier: TintModifier(style: style))
    }

    public func disabled(_ isDisabled: Bool = true) -> some View {
        _ModifierView(content: self, modifier: DisabledModifier(isDisabled: isDisabled))
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        _ModifierView(content: self, modifier: MultilineTextAlignmentModifier(alignment: alignment))
    }

    public func lineLimit(_ limit: Int?) -> some View {
        _ModifierView(content: self, modifier: LineLimitModifier(limit: limit))
    }

    /// At most `limit` lines — and, with `reservesSpace`, room for all of
    /// them even when fewer are used: a `Text` is then at least `limit`
    /// lines tall, and a vertical `TextField` keeps the room too.
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        lineLimits(lower: reservesSpace ? limit : 0, upper: limit)
    }

    /// Between `limit.lowerBound` and `limit.upperBound` lines. A `Text`
    /// keeps room for the lower bound however few lines it has; a vertical
    /// `TextField` keeps it too, and grows to the upper, then scrolls.
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        lineLimits(lower: limit.lowerBound, upper: limit.upperBound)
    }

    /// At least `limit.lowerBound` lines, with no upper limit.
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        lineLimits(lower: limit.lowerBound, upper: nil)
    }

    /// At most `limit.upperBound` lines.
    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View {
        lineLimits(lower: 0, upper: limit.upperBound)
    }

    private func lineLimits(lower: Int, upper: Int?) -> some View {
        _ModifierView(content: self, modifier: LineLimitsModifier(lower: lower, upper: upper))
    }
}

// MARK: - The modifiers
//
// Each writes its value where it goes. The node they put in the tree is
// an `EnvironmentContent`: almost everything they set is read while the
// views below are built, but dynamic colors are resolved as they are drawn,
// so the scheme in effect below travels with the draw context — whether or
// not the modifier is the one that set it.

/// `.environment(_:_:)`. Two applications are the same when the key path
/// is, and the values are equivalent as view inputs: equal, the same
/// object, the same bytes. A value there is no telling about — a closure —
/// makes it a new one each time.
struct EnvironmentKeyPathModifier<Value>: PrimitiveModifier {
    let keyPath: WritableKeyPath<EnvironmentValues, Value>
    let value: Value

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment[keyPath: keyPath] = value
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }

    func _isEquivalent(to other: EnvironmentKeyPathModifier<Value>) -> Bool {
        keyPath == other.keyPath && _areEquivalent(value, other.value)
    }
}

/// `.colorScheme(_:)`.
struct ColorSchemeModifier: PrimitiveModifier, Equatable {
    let scheme: ColorScheme

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.colorScheme = scheme
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.font(_:)`.
struct FontModifier: PrimitiveModifier, Equatable {
    let font: Font

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.font = font
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.foregroundColor(_:)`.
struct ForegroundColorModifier: PrimitiveModifier, Equatable {
    let color: Color

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.foregroundStyle = .color(color)
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.foregroundStyle(_:)` with a style.
struct ForegroundStyleModifier: PrimitiveModifier, Equatable {
    let style: ShapeStyle

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.foregroundStyle = style
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.foregroundStyle(_:)` with a color.
struct ForegroundStyleColorModifier: PrimitiveModifier, Equatable {
    let color: Color

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.foregroundStyle = .color(color)
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.tint(_:)` with a color.
struct TintColorModifier: PrimitiveModifier, Equatable {
    let color: Color

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.tint = .color(color)
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.tint(_:)` with a style.
struct TintModifier: PrimitiveModifier, Equatable {
    let style: ShapeStyle

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.tint = style
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.disabled(_:)`.
struct DisabledModifier: PrimitiveModifier, Equatable {
    let isDisabled: Bool

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.isEnabled = !isDisabled
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.multilineTextAlignment(_:)`.
struct MultilineTextAlignmentModifier: PrimitiveModifier, Equatable {
    let alignment: TextAlignment

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.multilineTextAlignment = alignment
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.lineLimit(_:)` with a count, or `nil` for none.
struct LineLimitModifier: PrimitiveModifier, Equatable {
    let limit: Int?

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.lineLimit = limit
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.lineLimit(_:reservesSpace:)` and the ranges: the upper limit, and the
/// lines kept room for.
struct LineLimitsModifier: PrimitiveModifier, Equatable {
    let lower: Int
    let upper: Int?

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.lineLimit = upper
        environment.reservedLineCount = lower
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

private struct ReservedLineCountKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// The lines a vertical text field keeps room for however few it uses —
    /// the lower end of `.lineLimit(2...5)`, or `.lineLimit(3, reservesSpace: true)`.
    var reservedLineCount: Int {
        get { self[ReservedLineCountKey.self] }
        set { self[ReservedLineCountKey.self] = newValue }
    }
}
