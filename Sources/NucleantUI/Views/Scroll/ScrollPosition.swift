//
//  ScrollPosition.swift
//  NucleantUI
//
//  Where a scroll view is, as a value the app holds in a binding: a view by
//  its id, an edge, a point. A new value written to the binding scrolls the
//  scroll view there, along the change's animation; the user scrolling it
//  writes back which view of its scroll target layout is now in front, and
//  that it was the user who put it there.
//
//  The scroll view keeps the value it was last given or wrote back
//  (`Scroller.lastPosition`), so the binding handing it back is not taken
//  for a new one.
//

/// A type that defines the semantic position of where a scroll view is
/// scrolled within its content.
///
/// Use this type along with the ``View/scrollPosition(_:anchor:)``
/// modifier to control where a scroll view is positioned. You
/// can use this type to scroll in a variety of ways:
///   - scroll to a view with a provided identity
///   - scroll to a concrete offset
///   - scroll to an edge
///
/// You can create a scroll position with a specified view identity type
///
///     @State private var position = ScrollPosition(idType: MyItem.ID.self)
///
/// SwiftUI will use that along with the views in the scroll view's
/// scroll target layout to programmatically scroll to those views and to
/// update the ``ScrollPosition/viewID`` property as the user scrolls.
/// Use the ``View/scrollTargetLayout()`` modifier to configure
/// which layout contains your scroll targets.
///
/// When scrolling to a view with an identifier, SwiftUI will update
/// the position with the value of the top-most view scrolled within
/// the visible region of the scroll view.
///
///     ScrollView {
///         LazyVStack {
///             ForEach(items) { item in
///                 ItemView(item)
///             }
///         }
///         .scrollTargetLayout()
///     }
///     .scrollPosition($position)
///
/// You can then query the currently scrolled id by using the
/// ``ScrollPosition/viewID(type:)``.
///
///     let viewID: MyItem.ID = position.viewID(type: MyItem.ID.self)
///
/// While most use cases will use view identity based scrolling, you
/// can also use the scroll position type to scroll to offsets or edges.
/// For example, you can create a button that scrolls to the bottom of
/// the scroll view by specifying an edge.
///
///     Button("Scroll to bottom") {
///         position.scrollTo(edge: .bottom)
///     }
///
/// When configuring a scroll position, SwiftUI will attempt to keep that
/// position stable. For an edge, that means keeping a top aligned
/// scroll view scrolled to the top if the content size changes.
/// For a point, SwiftUI won't attempt to keep that exact offset scrolled
/// when the content size changes nor will it update to a new offset
/// when that changes.
///
/// `viewID` is an `AnyHashable` here, where SwiftUI's is an existential of
/// `Hashable & Sendable`; `viewID(type:)` reads it as your id type.
public struct ScrollPosition: @unchecked Sendable {

    /// Where it says the scroll view is.
    enum Place: Equatable {
        /// Wherever the user put it.
        case automatic
        case edge(Edge)
        case point(Point)
        case x(Double)
        case y(Double)
        case view(AnyHashable, anchor: UnitPoint?)
    }

    private(set) var place: Place

    /// The view of the scroll target layout the user scrolled to, of the
    /// id type it was made for.
    private var scrolledViewID: AnyHashable?

    private var positionedByUser = false

    /// The id type of the views it reports the user scrolling to.
    private let idType: ObjectIdentifier

    /// That type's id of a view of the scroll target layout, if it has one.
    let identify: @MainActor @Sendable (ViewNode) -> AnyHashable?

    /// Where the view `place` names stands, for its own id type.
    private var findView: (@MainActor @Sendable (ViewNode) -> IdentifiedPlace?)?

    private init<T: Hashable & Sendable>(idType: T.Type, place: Place) {
        self.place = place
        self.idType = ObjectIdentifier(T.self)
        self.identify = { node in node.scrollTargetID(as: T.self).map(AnyHashable.init) }
    }

    /// Creates a new scroll position to a view with a provided identity value.
    ///
    /// The type of the ID indicates the type of ID of views within a
    /// scroll target layout the scroll view should look for.
    public init<ID: Hashable & Sendable>(id: ID, anchor: UnitPoint? = nil) {
        self.init(idType: ID.self, place: .view(AnyHashable(id), anchor: anchor))
        findView = { node in node.place(identifiedBy: id) }
    }

    /// Creates a new automatic scroll position.
    ///
    /// You can provide a type to the scroll position. This type should match
    /// the type of IDs associated to views in a scroll target layout. The
    /// scroll view will look for those views to update the value of
    /// the scroll position with.
    public init<T: Hashable & Sendable>(idType: T.Type = Never.self) {
        self.init(idType: T.self, place: .automatic)
    }

    /// Creates a new scroll position to be scrolled to the provided edge.
    public init<T: Hashable & Sendable>(idType: T.Type = Never.self, edge: Edge) {
        self.init(idType: T.self, place: .edge(edge))
    }

    /// Creates a new scroll position to be scrolled to the provided point.
    public init<T: Hashable & Sendable>(idType: T.Type = Never.self, point: Point) {
        self.init(idType: T.self, place: .point(point))
    }

    /// Creates a new scroll position to be scrolled to the provided x and y
    /// values.
    public init<T: Hashable & Sendable>(idType: T.Type = Never.self, x: Double, y: Double) {
        self.init(idType: T.self, place: .point(Point(x: x, y: y)))
    }

    /// Creates a new scroll position to be scrolled to the provided x value.
    public init<T: Hashable & Sendable>(idType: T.Type = Never.self, x: Double) {
        self.init(idType: T.self, place: .x(x))
    }

    /// Creates a new scroll position to be scrolled to the provided y value.
    public init<T: Hashable & Sendable>(idType: T.Type = Never.self, y: Double) {
        self.init(idType: T.self, place: .y(y))
    }

    // MARK: - Scrolling

    /// Scrolls the position of the scroll view to a view with a identity value
    /// and anchor you provide.
    ///
    /// Inform the scroll view of which layout it should look for view's
    /// with the identity value you provide using the
    /// ``View/scrollTargetLayout()`` modifier.
    public mutating func scrollTo<ID: Hashable & Sendable>(id: ID, anchor: UnitPoint? = nil) {
        place = .view(AnyHashable(id), anchor: anchor)
        findView = { node in node.place(identifiedBy: id) }
        moved()
    }

    /// Scrolls the position of the scroll view to the edge you provide.
    public mutating func scrollTo(edge: Edge) {
        place = .edge(edge)
        moved()
    }

    /// Scrolls the position of the scroll view to the point you provide.
    ///
    /// The scroll view will clamp this value to only scroll to the size of
    /// its actual content.
    public mutating func scrollTo(point: Point) {
        place = .point(point)
        moved()
    }

    /// Scrolls the position of the scroll view to the x and y value you
    /// provide.
    ///
    /// The scroll view will clamp this value to only scroll to the size of
    /// its actual content.
    public mutating func scrollTo(x: Double, y: Double) {
        place = .point(Point(x: x, y: y))
        moved()
    }

    /// Scrolls the position of the scroll view to the x value you provide.
    ///
    /// The scroll view chooses the y value based on the content insets of
    /// the scroll view and will clamp this value to only scroll to the
    /// size of its actual content.
    public mutating func scrollTo(x: Double) {
        place = .x(x)
        moved()
    }

    /// Scrolls the position of the scroll view to the y value you provide.
    ///
    /// The scroll view chooses the x value based on the content insets of
    /// the scroll view and will clamp this value to only scroll to the
    /// size of its actual content.
    public mutating func scrollTo(y: Double) {
        place = .y(y)
        moved()
    }

    /// Put somewhere by the app: no longer where the user left it.
    private mutating func moved() {
        positionedByUser = false
        scrolledViewID = nil
    }

    // MARK: - Reading

    /// Whether the scroll view has been positioned by the user.
    ///
    /// You can write to this property to control whether the scroll view
    /// acts as if it has been positioned by the user. If the position had
    /// a non-nil edge / point value, that value will become nil when
    /// setting this property to true.
    public var isPositionedByUser: Bool {
        get { positionedByUser }
        set {
            positionedByUser = newValue
            guard newValue else { return }
            switch place {
            case .edge, .point, .x, .y: place = .automatic
            case .automatic, .view: break
            }
        }
    }

    /// The positioned edge of the scroll view if configured to be in that
    /// position.
    public var edge: Edge? {
        if case .edge(let edge) = place { return edge }
        return nil
    }

    /// The positioned point of the scroll view if configured to be in that
    /// position.
    public var point: Point? {
        if case .point(let point) = place { return point }
        return nil
    }

    /// The type-erased id of the view positioned in the scroll view if
    /// configured to be in that position or the user has scrolled past a
    /// view with an id of matching type.
    public var viewID: AnyHashable? {
        if case .view(let id, _) = place { return id }
        return scrolledViewID
    }

    /// The id of the view positioned in the scroll view if configured
    /// to be in that position or the user has scrolled past a view with
    /// an id of matching type.
    public func viewID<T: Hashable & Sendable>(type: T.Type) -> T? {
        viewID.flatMap { $0 as? T }
    }

    /// This position after the user scrolled the scroll view so that
    /// `scrolledTo` — of the id type it reports — is the view in front.
    func scrolledByUser(to scrolledTo: AnyHashable?) -> ScrollPosition {
        var next = self
        next.place = .automatic
        next.positionedByUser = true
        next.scrolledViewID = scrolledTo
        next.findView = nil
        return next
    }

    /// Where the view it names stands, from the scroll view's node.
    @MainActor
    func viewPlace(in node: ViewNode) -> IdentifiedPlace? {
        findView?(node)
    }
}

extension ScrollPosition: Equatable {
    public static func == (lhs: ScrollPosition, rhs: ScrollPosition) -> Bool {
        lhs.place == rhs.place
            && lhs.scrolledViewID == rhs.scrolledViewID
            && lhs.positionedByUser == rhs.positionedByUser
            && lhs.idType == rhs.idType
    }
}

// MARK: - The modifiers

extension View {
    /// Associates a binding to a scroll position with a scroll view within
    /// this view.
    ///
    /// Use this modifier along with the ``ScrollPosition`` type to
    /// programmatically control the position of a scroll view: write a new
    /// position to the binding to scroll there — along the change's
    /// animation, in `withAnimation` — and read it to know which view of
    /// the scroll target layout the user has scrolled to.
    ///
    ///     @State private var position = ScrollPosition(idType: Item.ID.self)
    ///
    ///     ScrollView {
    ///         LazyVStack {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///         .scrollTargetLayout()
    ///     }
    ///     .scrollPosition($position)
    ///
    /// The anchor picks the view reported — the one under that point of
    /// the scroll view; without one, the first in view — and aligns a view
    /// scrolled to that has no anchor of its own.
    public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        _ModifierView(content: self, modifier: ScrollPositionModifier(position: position, anchor: anchor))
    }

    /// Associates a binding to be updated when a scroll view within this
    /// view scrolls.
    ///
    /// Use this modifier along with the ``View/scrollTargetLayout()``
    /// modifier to know the identity of the view that is actively
    /// scrolled. As the scroll view scrolls, the binding will be updated
    /// with the identity of the leading-most / top-most view.
    ///
    /// Use the ``View/scrollTargetLayout()`` modifier to configure
    /// which layout contains your scroll targets. When the scroll view
    /// is scrolled, the binding will be updated with the value of the
    /// view.
    ///
    ///     @Binding var items: [Item]
    ///     @Binding var scrolledID: Item.ID?
    ///
    ///     ScrollView {
    ///         LazyVStack {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///         .scrollTargetLayout()
    ///     }
    ///     .scrollPosition(id: $scrolledID)
    ///
    /// You can write to the binding to scroll to the view with
    /// the provided identity.
    ///
    ///     Button("Scroll to Top") {
    ///         scrolledID = items.first
    ///     }
    ///
    /// You can provide an anchor to this modifier to both:
    ///   - Influence which view the system chooses as the view whose
    ///     identity value will update the providing binding as the scroll
    ///     view scrolls.
    ///   - Control the alignment of the view when scrolling to a view
    ///     when writing a new binding value.
    ///
    /// If no anchor has been provided, SwiftUI will scroll the minimal amount
    /// when using the scroll position to programmatically scroll to a view.
    public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View {
        _ModifierView(content: self, modifier: ScrollPositionIDModifier(id: id, anchor: anchor))
    }
}

/// `.scrollPosition(_:anchor:)` as the environment carries it to the
/// scroll view below.
struct ScrollPositionEntry {
    let position: Binding<ScrollPosition>
    let anchor: UnitPoint?
}

/// `.scrollPosition(id:anchor:)` as the environment carries it: what the
/// scroll view does with it, made for the binding's id type.
struct ScrollPositionIDEntry {
    /// Take the binding's id, when it is not the one last seen: scroll to
    /// that view, along the build's animation.
    let follow: @MainActor (Scroller, Animation?) -> Void
    /// After the user scrolled: hand the binding the id of the view now in
    /// front, when it is another one.
    let report: @MainActor (Scroller, EffectQueue) -> Void
}

private struct ScrollPositionKey: EnvironmentKey {
    static var defaultValue: ScrollPositionEntry? { nil }
}

private struct ScrollPositionIDKey: EnvironmentKey {
    static var defaultValue: ScrollPositionIDEntry? { nil }
}

extension EnvironmentValues {
    var scrollPosition: ScrollPositionEntry? {
        get { self[ScrollPositionKey.self] }
        set { self[ScrollPositionKey.self] = newValue }
    }

    var scrollPositionID: ScrollPositionIDEntry? {
        get { self[ScrollPositionIDKey.self] }
        set { self[ScrollPositionIDKey.self] = newValue }
    }
}

struct ScrollPositionModifier: PrimitiveModifier {
    let position: Binding<ScrollPosition>
    let anchor: UnitPoint?

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.scrollPosition = ScrollPositionEntry(position: position, anchor: anchor)
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }

    func _isEquivalent(to other: ScrollPositionModifier) -> Bool {
        anchor == other.anchor && _areEquivalent(position, other.position)
    }
}

struct ScrollPositionIDModifier<ID: Hashable>: PrimitiveModifier {
    let id: Binding<ID?>
    let anchor: UnitPoint?

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        let binding = id
        let anchor = anchor
        environment.scrollPositionID = ScrollPositionIDEntry(
            follow: { scroller, animation in
                let wanted = binding.wrappedValue
                let key = wanted.map(AnyHashable.init)
                guard key != scroller.lastPositionID else { return }
                scroller.lastPositionID = key
                guard let wanted else { return }
                scroller.request({ scroller, node in
                    guard let place = node.place(identifiedBy: wanted) else { return nil }
                    let rect = scroller.contentRect(place.frame(along: scroller.axes))
                    return (scroller.offset(showing: rect, anchor: anchor), place.isBuilt)
                }, animation: animation)
            },
            report: { scroller, effects in
                guard let id = scroller.positionedView(anchor: anchor)?.scrollTargetID(as: ID.self) else { return }
                let key = AnyHashable(id)
                guard key != scroller.lastPositionID else { return }
                scroller.lastPositionID = key
                effects.afterPass { binding.wrappedValue = id }
            }
        )
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }

    func _isEquivalent(to other: ScrollPositionIDModifier<ID>) -> Bool {
        anchor == other.anchor && _areEquivalent(id, other.id)
    }
}

// MARK: - The scroll view's side

extension Scroller {
    /// Take `position` from the binding, when it is not the one last given
    /// or reported: scroll where it says, along `animation`. `anchor` is the
    /// modifier's, for a view position with none of its own.
    func follow(_ position: ScrollPosition, anchor: UnitPoint?, animation: Animation?) {
        guard position != lastPosition else { return }
        lastPosition = position
        switch position.place {
        case .automatic:
            break
        case .edge(let edge):
            pin(to: edge, animation: animation)
        case .point(let point):
            request({ scroller, _ in (scroller.clamped(point), true) }, animation: animation)
        case .x(let x):
            request({ scroller, _ in
                (scroller.clamped(Point(x: x, y: scroller.verticalBounds.lowerBound)), true)
            }, animation: animation)
        case .y(let y):
            request({ scroller, _ in
                (scroller.clamped(Point(x: scroller.horizontalBounds.lowerBound, y: y)), true)
            }, animation: animation)
        case .view(_, let own):
            let alignment = own ?? anchor
            request({ scroller, node in
                guard let place = scroller.lastPosition?.viewPlace(in: node) else { return nil }
                let rect = scroller.contentRect(place.frame(along: scroller.axes))
                return (scroller.offset(showing: rect, anchor: alignment), place.isBuilt)
            }, animation: animation)
        }
    }

    /// Where the user has scrolled it, as the next value of `position`'s
    /// binding — `nil` when that is the value it already has.
    func reportedPosition(anchor: UnitPoint?) -> ScrollPosition? {
        guard let last = lastPosition else { return nil }
        let front = positionedView(anchor: anchor).flatMap(last.identify)
        let next = last.scrolledByUser(to: front)
        guard next != last else { return nil }
        lastPosition = next
        return next
    }
}

extension ViewNode {
    /// The id of type `ID` this view of a scroll target layout has: from a
    /// `.id(_:)` on it, or as the element of the `ForEach` it is a row of.
    func scrollTargetID<ID: Hashable>(as type: ID.Type) -> ID? {
        // `.id(_:)` over the modifiers it is written under.
        var down: ViewNode = self
        while true {
            if let identified = down.content(as: IdentifiedContent<ID>.self) { return identified.id }
            guard down.children.count == 1 else { break }
            down = down.children[0]
        }
        // Up through what dissolved into the layout: `.id(_:)` written
        // around it, or the `ForEach` it is a row of.
        var probe: ViewNode = self
        while let parent = probe.parent {
            if let identified = parent.content(as: IdentifiedContent<ID>.self) { return identified.id }
            if let forEach = parent.content(as: ForEachContent<ID>.self) { return forEach.id(of: self) }
            guard parent.isTransparent else { return nil }
            probe = parent
        }
        return nil
    }
}
