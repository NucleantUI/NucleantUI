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

/// Everything the text modifiers above write, in one environment value: a
/// `Text` reads them in one lookup, and its view and every view around it
/// note one key read rather than ten. Each public value below reads and
/// writes its own field; a write reads the value first, so the modifier
/// that wrote it is rebuilt when a field set further out changes.
struct TextSettings: Hashable {
    var truncationMode = Text.TruncationMode.tail
    var lineSpacing = 0.0
    var allowsTightening = false
    var minimumScaleFactor = 1.0
    var textCase: Text.Case? = nil
    /// `.kerning(_:)` on a view: for the texts below that set none.
    var kerning: Double? = nil
    /// `.tracking(_:)` on a view: for the texts below that set none.
    var tracking: Double? = nil
    /// `.baselineOffset(_:)` on a view: for the texts below that set none.
    var baselineOffset: Double? = nil
    /// `.underline(_:pattern:color:)` on a view: for the texts below that
    /// set none. `nil` when turned off.
    var underline: Text.LineStyle? = nil
    /// `.strikethrough(_:pattern:color:)` on a view: for the texts below
    /// that set none. `nil` when turned off.
    var strikethrough: Text.LineStyle? = nil
}

private struct TextSettingsKey: EnvironmentKey {
    static let defaultValue = TextSettings()
}

private struct LocaleKey: EnvironmentKey {
    static let defaultValue = Locale.autoupdatingCurrent
}

extension EnvironmentValues {

    /// The text settings, all at once — what a `Text` reads.
    var textSettings: TextSettings {
        get { self[TextSettingsKey.self] }
        set { self[TextSettingsKey.self] = newValue }
    }

    /// Where a text cuts the last line it shows when it doesn't fit.
    /// `.tail` unless set.
    public var truncationMode: Text.TruncationMode {
        get { self[TextSettingsKey.self].truncationMode }
        set { self[TextSettingsKey.self].truncationMode = newValue }
    }

    /// The space between the bottom of one line of text and the top of the
    /// next, in points. Laid out as 0 when negative.
    public var lineSpacing: Double {
        get { self[TextSettingsKey.self].lineSpacing }
        set { self[TextSettingsKey.self].lineSpacing = newValue }
    }

    /// Whether text may move its characters closer together to fit a line
    /// before it is cut. `false` unless set.
    public var allowsTightening: Bool {
        get { self[TextSettingsKey.self].allowsTightening }
        set { self[TextSettingsKey.self].allowsTightening = newValue }
    }

    /// The smallest fraction of its font size a text may be set at to fit.
    /// Above 0 and at most 1; anything else is stored as 1, which never
    /// shrinks.
    public var minimumScaleFactor: Double {
        get { self[TextSettingsKey.self].minimumScaleFactor }
        set { self[TextSettingsKey.self].minimumScaleFactor = newValue > 0 && newValue <= 1 ? newValue : 1 }
    }

    /// The case texts are shown in; `nil` shows them as written.
    public var textCase: Text.Case? {
        get { self[TextSettingsKey.self].textCase }
        set { self[TextSettingsKey.self].textCase = newValue }
    }

    /// The locale text is shown for: what `textCase` changes the case
    /// with. The system's own unless set.
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }

    var defaultKerning: Double? {
        get { self[TextSettingsKey.self].kerning }
        set { self[TextSettingsKey.self].kerning = newValue }
    }

    var defaultTracking: Double? {
        get { self[TextSettingsKey.self].tracking }
        set { self[TextSettingsKey.self].tracking = newValue }
    }

    var defaultBaselineOffset: Double? {
        get { self[TextSettingsKey.self].baselineOffset }
        set { self[TextSettingsKey.self].baselineOffset = newValue }
    }

    var defaultUnderline: Text.LineStyle? {
        get { self[TextSettingsKey.self].underline }
        set { self[TextSettingsKey.self].underline = newValue }
    }

    var defaultStrikethrough: Text.LineStyle? {
        get { self[TextSettingsKey.self].strikethrough }
        set { self[TextSettingsKey.self].strikethrough = newValue }
    }
}
