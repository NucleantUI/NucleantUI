//
//  GeometryProxy.swift
//  NucleantUI
//
//  What a `GeometryReader` hands its content, and what `.onGeometryChange`
//  hands its transform: where the view was placed, answered in whichever
//  coordinate space is asked for.
//
//  A view's rect is in layout space — window points before any rotation or
//  scale — and the transform it was drawn under takes that to the window.
//  Every answer goes through both, so a reader inside a `.scaleEffect`
//  reports the box it covers on screen, as SwiftUI's does.
//

/// A proxy for access to the size and coordinate space (for anchor resolution)
/// of the container view.
public struct GeometryProxy {

    /// Where the container was placed when this proxy was made — what two
    /// proxies are compared by.
    let geometry: PlacedGeometry

    /// A `GeometryReader`'s record of what its content read, and of where
    /// the reader is now; `nil` for a proxy that is only asked once, as
    /// `.onGeometryChange`'s is.
    let log: GeometryReadLog?

    init(geometry: PlacedGeometry, log: GeometryReadLog?) {
        self.geometry = geometry
        self.log = log
    }

    /// Where the container is now. A reader's proxy kept past the build —
    /// in a gesture's action, say — answers for where the reader is now,
    /// not for where it was when the content was built.
    private var placed: PlacedGeometry {
        log?.current ?? geometry
    }

    /// The size of the container view.
    public var size: Size {
        log?.noteSize()
        return placed.rect.size
    }

    /// The safe area inset of the container view.
    ///
    /// Zero: NucleantUI has no safe areas yet — every view is laid out over
    /// the whole window.
    public var safeAreaInsets: EdgeInsets {
        EdgeInsets()
    }

    /// Returns the container view's bounds rectangle, converted to a defined
    /// coordinate space.
    ///
    /// A name no ancestor gave its space measures in the window, as
    /// `.global` does.
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> Rect {
        let space = coordinateSpace.coordinateSpace
        log?.noteFrame(in: space)
        return placed.frame(in: space)
    }

    /// Returns the given coordinate space's bounds rectangle, converted to the
    /// local coordinate space.
    ///
    /// `nil` when no ancestor gave its space that name.
    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> Rect? {
        log?.noteBounds(of: coordinateSpace.name)
        return placed.bounds(of: coordinateSpace.name)
    }
}

/// Two proxies are the same input when they come from the same reader and
/// were made at the same place: a view handed a proxy builds the same
/// thing from either.
extension GeometryProxy: ViewInput {
    public func _isEquivalent(to other: GeometryProxy) -> Bool {
        log === other.log && geometry == other.geometry
    }
}

/// Where a view was placed: its rect in layout space, the transform it was
/// drawn under, and the named spaces above it — everything a proxy answers
/// from.
struct PlacedGeometry: Equatable {
    var rect: Rect
    var transform: Transform
    var spaces: [CoordinateSpaceFrame]

    /// The rect as seen from `space` — the box around it, when a rotation
    /// stands between the two.
    func frame(in space: CoordinateSpace) -> Rect {
        switch space {
        case .local:
            return Rect(origin: .zero, size: rect.size)
        case .global:
            return rect.applying(transform)
        case .named(let name):
            guard let named = innermost(name) else {
                return rect.applying(transform)
            }
            // Out to the window, then back into the named view's layout
            // space, and from there to its own top-leading corner. A space
            // scaled to nothing has no inside to measure in; it is taken
            // as unscaled.
            let intoNamed = (named.transform.inverted() ?? .identity).concatenating(transform)
            return rect.applying(intoNamed)
                .offsetBy(dx: -named.rect.minX, dy: -named.rect.minY)
        }
    }

    /// The named view's own rect as seen from this view, or `nil` when no
    /// ancestor has that name.
    func bounds(of name: AnyHashable) -> Rect? {
        guard let named = innermost(name) else { return nil }
        let intoSelf = (transform.inverted() ?? .identity).concatenating(named.transform)
        return named.rect.applying(intoSelf)
            .offsetBy(dx: -rect.minX, dy: -rect.minY)
    }

    /// The nearest ancestor with `name` — a scroll view inside a scroll
    /// view means the inner one.
    private func innermost(_ name: AnyHashable) -> CoordinateSpaceFrame? {
        spaces.last { $0.name == name }
    }
}

/// What a `GeometryReader`'s content has asked its proxy, and where the
/// reader was last placed and built.
///
/// Placement builds the content again only when an answer it asked for
/// would now come out different: content that read only the size is left
/// standing while a scroll moves the reader, and content that asked for its
/// frame in the scroll view is built again on every step. What was asked
/// is only ever added to — a view reused from an earlier build asked when
/// it was built, and still depends on the answer.
final class GeometryReadLog {

    /// Where the reader is now: set each time it is placed.
    var current: PlacedGeometry?

    /// Where the reader was when its standing content was built.
    var builtWith: PlacedGeometry?

    private var readsSize = false
    private var frames: Set<CoordinateSpace> = []
    private var bounds: Set<AnyHashable> = []

    func noteSize() {
        readsSize = true
    }

    func noteFrame(in space: CoordinateSpace) {
        frames.insert(space)
    }

    func noteBounds(of name: AnyHashable) {
        bounds.insert(name)
    }

    /// Whether anything the content asked comes out different at `new`
    /// than at `old`.
    func answersDiffer(between old: PlacedGeometry, and new: PlacedGeometry) -> Bool {
        if readsSize && old.rect.size != new.rect.size { return true }
        for space in frames where old.frame(in: space) != new.frame(in: space) {
            return true
        }
        for name in bounds where old.bounds(of: name) != new.bounds(of: name) {
            return true
        }
        return false
    }
}
