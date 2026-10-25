//
//  CoordinateSpace.swift
//  NucleantUI
//
//  The frames of reference a `GeometryProxy` measures in: the window
//  (`.global`), the view itself (`.local`), and an ancestor's own space —
//  one named with `.coordinateSpace(_:)`, or a scroll view's (`.named`,
//  `.scrollView`). A named space is found during placement, not while
//  building: the ancestor puts where it was placed into the `DrawContext`
//  its subtree is placed under, and a proxy below looks it up there.
//

/// A resolved coordinate space created by the coordinate space protocol.
///
/// You don't typically use `CoordinateSpace` directly. Instead, use the static
/// properties and functions of `CoordinateSpaceProtocol` such as `.global`,
/// `.local`, and `.named(_:)`.
public enum CoordinateSpace {

    /// The global coordinate space at the root of the view hierarchy.
    case global

    /// The local coordinate space of the current view.
    case local

    /// A named reference to a view's local coordinate space.
    case named(AnyHashable)
}

extension CoordinateSpace {

    public var isGlobal: Bool {
        if case .global = self { return true }
        return false
    }

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

extension CoordinateSpace: Equatable, Hashable {}

/// A frame of reference within the layout system.
///
/// All geometric properties of a view, including size, position, and
/// transform, are defined within the local coordinate space of the view's
/// parent. These values can be converted into other coordinate spaces
/// by passing types conforming to this protocol into functions such as
/// `GeometryProxy.frame(in:)`.
///
/// For example, a named coordinate space allows you to convert the frame
/// of a view into the local coordinate space of an ancestor view by defining
/// a named coordinate space using the `coordinateSpace(_:)` modifier, then
/// passing that same named coordinate space into the `frame(in:)` function.
///
/// ```swift
/// VStack {
///     GeometryReader { geometryProxy in
///         let distanceFromTop = geometryProxy.frame(in: .named("container")).origin.y
///         Text("This view is \(distanceFromTop) points from the top of the VStack")
///     }
///     .padding()
/// }
/// .coordinateSpace(.named("container"))
/// ```
///
/// You don't typically create types conforming to this protocol yourself.
/// Instead, use the system-provided `.global`, `.local`, and `.named(_:)`
/// implementations.
public protocol CoordinateSpaceProtocol {

    /// The resolved coordinate space.
    var coordinateSpace: CoordinateSpace { get }
}

/// The global coordinate space at the root of the view hierarchy.
///
/// Here that is the window's content: points from its top-leading corner.
public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {

    public init() {}

    /// The resolved coordinate space.
    public var coordinateSpace: CoordinateSpace { .global }
}

/// The local coordinate space of the current view.
public struct LocalCoordinateSpace: CoordinateSpaceProtocol {

    public init() {}

    /// The resolved coordinate space.
    public var coordinateSpace: CoordinateSpace { .local }
}

/// A named coordinate space.
///
/// Use the `coordinateSpace(_:)` modifier to assign a name to the local
/// coordinate space of a  parent view. Child views can then refer to that
/// coordinate space using `.named(_:)`.
public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {

    let name: AnyHashable

    init(name: AnyHashable) {
        self.name = name
    }

    /// The resolved coordinate space.
    public var coordinateSpace: CoordinateSpace { .named(name) }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {

    /// Creates a named coordinate space using the given value.
    ///
    /// Use the `coordinateSpace(_:)` modifier to assign a name to the local
    /// coordinate space of a  parent view. Child views can then refer to that
    /// coordinate space using `.named(_:)`.
    ///
    /// - Parameter name: A unique value that identifies the coordinate space.
    ///
    /// - Returns: A named coordinate space identified by the given value.
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: AnyHashable(name))
    }
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {

    /// The local coordinate space of the current view.
    public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {

    /// The global coordinate space at the root of the view hierarchy.
    public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {

    /// The named coordinate space that is added by the system for the innermost
    /// containing scroll view that allows scrolling along the provided axis.
    public static func scrollView(axis: Axis) -> Self {
        NamedCoordinateSpace(name: AnyHashable(ScrollViewSpaceName(axis: axis)))
    }

    /// The named coordinate space that is added by the system for the innermost
    /// containing scroll view.
    public static var scrollView: NamedCoordinateSpace {
        NamedCoordinateSpace(name: AnyHashable(ScrollViewSpaceName(axis: nil)))
    }
}

/// The names a `ScrollView` gives its visible rect: one for any scroll
/// view, and one for each axis it scrolls along. A private type, so no name
/// an app chooses can be one of them.
struct ScrollViewSpaceName: Hashable {
    let axis: Axis?
}

/// A named space as it was placed: the rect of the view that named it, in
/// layout space, and the transform that view was drawn under. Carried in
/// `DrawContext.coordinateSpaces`, innermost last.
///
/// `@unchecked Sendable` for `DrawContext`'s sake: a name is any `Hashable`,
/// as in SwiftUI, and placement only runs on the main actor.
struct CoordinateSpaceFrame: Equatable, @unchecked Sendable {
    let name: AnyHashable
    let rect: Rect
    let transform: Transform
}
