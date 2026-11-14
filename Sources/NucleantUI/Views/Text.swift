//
//  Text.swift
//  NucleantUI
//

import Foundation

/// A view that displays one or more lines of text.
///
/// ```swift
/// Text("Hello, World!")
///     .font(.title)
///     .foregroundColor(.white)
/// ```
@View
public struct Text {
    public let content: String

    // What the text's own modifiers set; `nil` inherits from the
    // environment, which is what the same modifier on a view around it
    // sets. Each is set by the modifier nearest the text, as in SwiftUI:
    // `Text("a").font(.title).font(.body)` is in the title font, and one
    // further out only fills in what is still unset.
    var explicitFont: Font?
    var explicitStyle: AnyShapeStyle?
    var explicitWeight: FontWeight?
    var isItalic = false
    var alignment: TextAlignment?
    var explicitLineLimit: Int??
    var explicitKerning: Double?
    var explicitTracking: Double?
    var explicitBaselineOffset: Double?
    /// `.some(nil)` when turned off on the text itself, over a line asked
    /// for by a view around it.
    var explicitUnderline: Text.LineStyle??
    var explicitStrikethrough: Text.LineStyle??

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
        if copy.explicitFont == nil { copy.explicitFont = font }
        return copy
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        if copy.explicitStyle == nil { copy.explicitStyle = AnyShapeStyle(color) }
        return copy
    }

    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        var copy = self
        if copy.explicitStyle == nil { copy.explicitStyle = AnyShapeStyle(style) }
        return copy
    }

    public func fontWeight(_ weight: FontWeight) -> Text {
        var copy = self
        if copy.explicitWeight == nil { copy.explicitWeight = weight }
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
        if copy.alignment == nil { copy.alignment = alignment }
        return copy
    }

    public func lineLimit(_ limit: Int?) -> Text {
        var copy = self
        if copy.explicitLineLimit == nil { copy.explicitLineLimit = .some(limit) }
        return copy
    }

    /// Moves the characters apart by `kerning` points after each one, or
    /// closer together when negative. 0 is the font's own spacing. A text
    /// with both kerning and tracking uses the tracking.
    public func kerning(_ kerning: Double) -> Text {
        var copy = self
        if copy.explicitKerning == nil { copy.explicitKerning = kerning }
        return copy
    }

    /// Adds `tracking` points after every character, or takes them away
    /// when negative. 0 is the font's own spacing. A text with both kerning
    /// and tracking uses the tracking.
    public func tracking(_ tracking: Double) -> Text {
        var copy = self
        if copy.explicitTracking == nil { copy.explicitTracking = tracking }
        return copy
    }

    /// Moves the text up from its baseline by `baselineOffset` points, or
    /// down when negative. The text's box grows to keep it inside.
    public func baselineOffset(_ baselineOffset: Double) -> Text {
        var copy = self
        if copy.explicitBaselineOffset == nil { copy.explicitBaselineOffset = baselineOffset }
        return copy
    }

    /// A solid line along the baseline, in `color` or, when that is `nil`,
    /// in the text's own color.
    public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text {
        var copy = self
        if copy.explicitUnderline == nil {
            copy.explicitUnderline = .some(isActive ? Text.LineStyle(pattern: .solid, color: color) : nil)
        }
        return copy
    }

    /// A line along the baseline in `pattern`, in `color` or, when that is
    /// `nil`, in the text's own color.
    public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern, color: Color? = nil) -> Text {
        var copy = self
        if copy.explicitUnderline == nil {
            copy.explicitUnderline = .some(isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
        }
        return copy
    }

    /// A solid line through the middle of the text, in `color` or, when that
    /// is `nil`, in the text's own color.
    public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text {
        var copy = self
        if copy.explicitStrikethrough == nil {
            copy.explicitStrikethrough = .some(isActive ? Text.LineStyle(pattern: .solid, color: color) : nil)
        }
        return copy
    }

    /// A line through the middle of the text in `pattern`, in `color` or,
    /// when that is `nil`, in the text's own color.
    public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern, color: Color? = nil) -> Text {
        var copy = self
        if copy.explicitStrikethrough == nil {
            copy.explicitStrikethrough = .some(isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
        }
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
        let environment = context.environment
        var font = explicitFont ?? environment.font
        if let explicitWeight { font.weight = explicitWeight }
        if isItalic { font.isItalic = true }

        // Every setting the view text modifiers write, in one read.
        let settings = environment.textSettings

        // The case is changed before anything is measured, in the
        // environment's language: "straße" is "STRASSE", and in Turkish
        // "istanbul" is "İSTANBUL".
        let string: String
        switch settings.textCase {
        case .uppercase?: string = content.uppercased(with: environment.locale)
        case .lowercase?: string = content.lowercased(with: environment.locale)
        case nil: string = content
        }

        // Resolved where the text is built, in its environment.
        let style = (explicitStyle ?? environment.foregroundStyle).paint(in: environment)
        let tracking = explicitTracking ?? settings.tracking
        let kerning = explicitKerning ?? settings.kerning
        let input = TextLayoutInput(
            string: string,
            font: font,
            letterSpacing: tracking ?? kerning ?? 0,
            baselineOffset: explicitBaselineOffset ?? settings.baselineOffset ?? 0,
            paragraph: TextParagraphStyle(
                lineLimit: explicitLineLimit ?? environment.lineLimit,
                reservedLines: environment.reservedLineCount,
                truncationMode: settings.truncationMode,
                lineSpacing: settings.lineSpacing,
                allowsTightening: settings.allowsTightening,
                minimumScaleFactor: settings.minimumScaleFactor
            )
        )
        return ContentNode(content: TextContent(
            input: input,
            face: TextMeasurer.face(resolving: input.font),
            style: style,
            alignment: alignment ?? environment.multilineTextAlignment,
            underline: explicitUnderline ?? settings.underline,
            strikethrough: explicitStrikethrough ?? settings.strikethrough,
            animatedColor: context.animatedValue(.textColor, style.animatableVector)
        ))
    }
}
