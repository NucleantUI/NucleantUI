//
//  TextStyles.swift
//  NucleantUI
//
//  The small values the text modifiers take: where a line too long for its
//  box is cut, how the case of a text is changed, and the line drawn under
//  or through it.
//

extension Text {

    /// Where a line of text too long for its box is cut, and the ellipsis
    /// goes.
    ///
    /// Only the last line a text shows is cut; every line before it wraps by
    /// word. Set it for the texts in a view with
    /// ``View/truncationMode(_:)``.
    public enum TruncationMode: Hashable, Sendable {
        /// Cut at the start: "…wxyz". The line shows the end of the text.
        case head
        /// Cut at the end: "abcd…".
        case tail
        /// Cut in the middle: "ab…yz".
        case middle
    }

    /// How the characters of a text are capitalized when it is shown.
    ///
    /// Set it for the texts in a view with ``View/textCase(_:)``. The case
    /// is changed with the environment's locale, before the text is
    /// measured.
    public enum Case: Hashable, Sendable {
        /// "Hello" shown as "HELLO".
        case uppercase
        /// "Hello" shown as "hello".
        case lowercase
    }

    /// A line drawn under a text (``Text/underline(_:color:)``) or through
    /// it (``Text/strikethrough(_:color:)``).
    public struct LineStyle: Hashable, Sendable {
        /// Solid, dotted or dashed.
        public var pattern: Pattern
        /// The line's color; `nil` draws it in the text's own color.
        public var color: Color?

        /// A line in `pattern`, in `color` or, when that is `nil`, in the
        /// color of the text.
        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        /// One solid line, in the color of the text.
        public static let single = LineStyle()

        /// The pattern of a ``Text/LineStyle``: solid, or a repeating run
        /// of dots and dashes.
        public struct Pattern: Hashable, Sendable {
            /// On and off lengths, in multiples of the line's thickness;
            /// empty for a solid line.
            let intervals: [Double]

            /// A solid line.
            public static let solid = Pattern(intervals: [])
            /// A line of dots.
            public static let dot = Pattern(intervals: [1, 1.5])
            /// A line of dashes.
            public static let dash = Pattern(intervals: [4, 2])
            /// A line of alternating dashes and dots.
            public static let dashDot = Pattern(intervals: [4, 2, 1, 2])
            /// A line of alternating dashes and two dots.
            public static let dashDotDot = Pattern(intervals: [4, 2, 1, 2, 1, 2])
        }
    }
}
