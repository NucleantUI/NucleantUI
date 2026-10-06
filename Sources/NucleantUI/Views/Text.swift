//
//  Text.swift
//  NucleantUI
//

/// A view that displays one or more lines of text.
///
/// ```swift
/// Text("Hello, World!")
///     .font(.title)
///     .foregroundColor(.white)
/// ```
@View
public struct Text: View {
    public let content: String

    /// Set by `.font(_:)` on the `Text` itself; `nil` inherits from the
    /// environment, which is what `.font(_:)` applied further up sets.
    var explicitFont: Font?
    var explicitColor: Color?
    var explicitWeight: FontWeight?
    var isItalic = false
    var alignment: TextAlignment?
    var explicitLineLimit: Int??

    public init(_ content: String, _viewID: ViewID = #viewID) {
        self.content = content
        self._viewID = _viewID
    }

    public init<S: StringProtocol>(_ content: S, _viewID: ViewID = #viewID) {
        self.content = String(content)
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }
}

extension Text {
    public func font(_ font: Font) -> Text {
        var copy = self
        copy.explicitFont = font
        return copy
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        copy.explicitColor = color
        return copy
    }

    public func fontWeight(_ weight: FontWeight) -> Text {
        var copy = self
        copy.explicitWeight = weight
        return copy
    }

    public func bold() -> Text { fontWeight(.bold) }

    public func italic() -> Text {
        var copy = self
        copy.isItalic = true
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineLimit(_ limit: Int?) -> Text {
        var copy = self
        copy.explicitLineLimit = .some(limit)
        return copy
    }
}

// `Text` is deliberately not `ExpressibleByStringLiteral` — SwiftUI's isn't
// either, and the conformance costs every text in the program its identity.
// `Text("…")` with a literal is read by the compiler as the literal becoming
// a `Text`, not as a call to `init(_:_viewID:)`, so the `#viewID` default
// never runs and the view falls back to `ViewID.unknown`: inside a body the
// builder's stamp covers it, but a `Text` built anywhere else — as a plain
// argument, in a `let`, in a ternary passed to a modifier — is then told
// apart from every other `Text` by position and type alone.

extension Text: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        var font = explicitFont ?? context.environment.font
        if let explicitWeight { font.weight = explicitWeight }
        if isItalic { font.isItalic = true }

        let color = explicitColor ?? context.environment.foregroundColor
        return ViewNode(content: TextContent(
            string: content,
            font: font,
            color: color,
            alignment: alignment ?? context.environment.multilineTextAlignment,
            lineLimit: explicitLineLimit ?? context.environment.lineLimit,
            animatedColor: context.animatedValue(.textColor, color.animatableVector)
        ))
    }
}
