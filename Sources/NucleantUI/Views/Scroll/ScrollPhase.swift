//
//  ScrollPhase.swift
//  NucleantUI
//

/// A type that describes the state of a scroll gesture of a
/// scrollable view like a scroll view.
///
/// A scroll gesture can be in one of four phases:
///     - idle: No active scroll is occurring.
///     - panning: An active scroll being driven by the user
///       is occurring.
///     - decelerating: The user has stopped driving a scroll
///       and the scroll view is decelerating to its final
///       target.
///     - animating: The system is animating to a final target
///       as a result of a programmatic animated scroll from
///       using a ``ScrollViewReader`` or
///      ``View/scrollPosition(id:anchor:)`` modifier.
public enum ScrollPhase: Hashable, Sendable {
    /// The idle phase where no kind of scrolling is occurring.
    case idle

    /// The tracking phase where the scroll view is tracking
    /// a potential scroll by the user but the user hasn't started
    /// a scroll.
    ///
    /// For example, on iOS, the user may start touching content
    /// inside of the scroll view. Until the user moves their finger
    /// the scroll view would be tracking the the finger. Not all
    /// platforms or kinds of scroll may trigger this phase.
    case tracking

    /// The interacting phase where the user is interacting
    /// with the scroll view.
    case interacting

    /// The decelerating phase where the user use has stopped
    /// interacting with the scroll view and the scroll view
    /// is decelerating towards its final target.
    case decelerating

    /// The animating phase where the scroll view is animating
    /// towards a final target.
    ///
    /// This phase is the result of a programmatic
    /// scroll when using a ``ScrollViewReader`` or
    /// ``View/scrollPosition(id:anchor:)`` modifier.
    case animating

    /// Whether the scroll view is actively scrolling.
    ///
    /// This convenience is equivalent to `phase != .idle`.
    public var isScrolling: Bool { self != .idle }
}

extension ScrollPhase: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .idle: "idle"
        case .tracking: "tracking"
        case .interacting: "interacting"
        case .decelerating: "decelerating"
        case .animating: "animating"
        }
    }
}
