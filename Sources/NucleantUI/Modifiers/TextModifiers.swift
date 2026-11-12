//
//  TextModifiers.swift
//  NucleantUI
//
//  The text settings a view hands down to every `Text` inside it: where a
//  line too long is cut, the space between lines, tightening and shrinking
//  to fit, the case of the characters. And defaults for what a `Text` may
//  also set on itself (kerning, tracking, the baseline offset, underline
//  and strikethrough), used where the text sets none.
//

import Foundation

extension View {

    /// Where the texts in this view cut the last line they show when the
    /// text doesn't fit: at its start, in its middle or at its end.
    ///
    /// ```swift
    /// Text(path)
    ///     .lineLimit(1)
    ///     .truncationMode(.middle)
    /// ```
    public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }

    /// The space, in points, between the bottom of one line and the top of
    /// the next, for the texts in this view.
    public func lineSpacing(_ lineSpacing: Double) -> some View {
        environment(\.lineSpacing, lineSpacing)
    }

    /// Whether the texts in this view may move their characters a little
    /// closer together to fit a line, before they cut it.
    public func allowsTightening(_ flag: Bool) -> some View {
        environment(\.allowsTightening, flag)
    }

    /// How small the texts in this view may be set to fit, as a fraction of
    /// their font size from 0 to 1. A text that doesn't fit even at that
    /// size is drawn at it and cut; one that is set smaller also takes less
    /// room.
    ///
    /// ```swift
    /// Text("This is a long label that will be scaled to fit:")
    ///     .lineLimit(1)
    ///     .minimumScaleFactor(0.5)
    /// ```
    public func minimumScaleFactor(_ factor: Double) -> some View {
        environment(\.minimumScaleFactor, factor)
    }

    /// Shows the texts in this view in upper or lower case, changed with the
    /// environment's locale; `nil` shows them as written.
    public func textCase(_ textCase: Text.Case?) -> some View {
        environment(\.textCase, textCase)
    }

    /// The kerning of the texts in this view that set none of their own:
    /// points added after every character, or taken away when negative.
    public func kerning(_ kerning: Double) -> some View {
        environment(\.defaultKerning, kerning)
    }

    /// The tracking of the texts in this view that set none of their own:
    /// points added after every character. A text with both tracking and
    /// kerning uses the tracking.
    public func tracking(_ tracking: Double) -> some View {
        environment(\.defaultTracking, tracking)
    }

    /// Moves the text in this view up (or down, when negative) from its
    /// baseline, in texts that set no offset of their own.
    public func baselineOffset(_ baselineOffset: Double) -> some View {
        environment(\.defaultBaselineOffset, baselineOffset)
    }

    /// A line along the baseline of the texts in this view that don't set
    /// their own, in `color` or, when that is `nil`, in each text's color.
    public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        environment(\.defaultUnderline, isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
    }

    /// A line through the middle of the texts in this view that don't set
    /// their own, in `color` or, when that is `nil`, in each text's color.
    public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        environment(\.defaultStrikethrough, isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
    }
}

// MARK: - Environment

private struct TruncationModeKey: EnvironmentKey {
    static let defaultValue = Text.TruncationMode.tail
}

private struct LineSpacingKey: EnvironmentKey {
    static let defaultValue = 0.0
}

private struct AllowsTighteningKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MinimumScaleFactorKey: EnvironmentKey {
    static let defaultValue = 1.0
}

private struct TextCaseKey: EnvironmentKey {
    static let defaultValue: Text.Case? = nil
}

private struct LocaleKey: EnvironmentKey {
    static let defaultValue = Locale.autoupdatingCurrent
}

private struct DefaultKerningKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

private struct DefaultTrackingKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

private struct DefaultBaselineOffsetKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

private struct DefaultUnderlineKey: EnvironmentKey {
    static let defaultValue: Text.LineStyle? = nil
}

private struct DefaultStrikethroughKey: EnvironmentKey {
    static let defaultValue: Text.LineStyle? = nil
}

extension EnvironmentValues {

    /// Where a text cuts the last line it shows when it doesn't fit.
    /// `.tail` unless set.
    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }

    /// The space between the bottom of one line of text and the top of the
    /// next, in points. Laid out as 0 when negative.
    public var lineSpacing: Double {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = newValue }
    }

    /// Whether text may move its characters closer together to fit a line
    /// before it is cut. `false` unless set.
    public var allowsTightening: Bool {
        get { self[AllowsTighteningKey.self] }
        set { self[AllowsTighteningKey.self] = newValue }
    }

    /// The smallest fraction of its font size a text may be set at to fit.
    /// Above 0 and at most 1; anything else is stored as 1, which never
    /// shrinks.
    public var minimumScaleFactor: Double {
        get { self[MinimumScaleFactorKey.self] }
        set { self[MinimumScaleFactorKey.self] = newValue > 0 && newValue <= 1 ? newValue : 1 }
    }

    /// The case texts are shown in; `nil` shows them as written.
    public var textCase: Text.Case? {
        get { self[TextCaseKey.self] }
        set { self[TextCaseKey.self] = newValue }
    }

    /// The locale text is shown for: what `textCase` changes the case
    /// with. The system's own unless set.
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }

    /// `.kerning(_:)` on a view: for the texts below that set none.
    var defaultKerning: Double? {
        get { self[DefaultKerningKey.self] }
        set { self[DefaultKerningKey.self] = newValue }
    }

    /// `.tracking(_:)` on a view: for the texts below that set none.
    var defaultTracking: Double? {
        get { self[DefaultTrackingKey.self] }
        set { self[DefaultTrackingKey.self] = newValue }
    }

    /// `.baselineOffset(_:)` on a view: for the texts below that set none.
    var defaultBaselineOffset: Double? {
        get { self[DefaultBaselineOffsetKey.self] }
        set { self[DefaultBaselineOffsetKey.self] = newValue }
    }

    /// `.underline(_:pattern:color:)` on a view: for the texts below that
    /// set none. `nil` when turned off.
    var defaultUnderline: Text.LineStyle? {
        get { self[DefaultUnderlineKey.self] }
        set { self[DefaultUnderlineKey.self] = newValue }
    }

    /// `.strikethrough(_:pattern:color:)` on a view: for the texts below
    /// that set none. `nil` when turned off.
    var defaultStrikethrough: Text.LineStyle? {
        get { self[DefaultStrikethroughKey.self] }
        set { self[DefaultStrikethroughKey.self] = newValue }
    }
}
