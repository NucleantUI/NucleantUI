//
//  ScrollTargetBehavior.swift
//  NucleantUI
//
//  Where a scroll may come to rest. A scroll view works out where a scroll
//  would end on its own — let go of, a finger's speed carrying it on; a
//  wheel gone still — and asks the behavior in its environment to move that
//  target: to a page, to a view's edge, anywhere. Then it springs there, as
//  fast as it was going.
//

/// A type defining the target in which a scroll view should try and scroll to.
public struct ScrollTarget: Hashable, Sendable {
    /// The rect that a scrollable view should try and have contained.
    public var rect: Rect

    /// The anchor to which the rect should be aligned within the visible
    /// region of the scrollable view.
    public var anchor: UnitPoint?

    init(rect: Rect, anchor: UnitPoint? = nil) {
        self.rect = rect
        self.anchor = anchor
    }
}

/// A type that defines the scroll behavior of a scrollable view.
///
/// A scrollable view calculates where scroll gestures should end using its
/// deceleration rate and the state of its scroll gesture by default. A scroll
/// behavior allows for customizing this logic.
///
/// You define a scroll behavior using the
/// ``ScrollTargetBehavior/updateTarget(_:context:)`` method.
///
/// Using this method, you can control where someone can scroll in a scrollable
/// view. For example, you can create a custom scroll behavior
/// that aligns to every 10 points by doing the following:
///
///     struct BasicScrollTargetBehavior: ScrollTargetBehavior {
///         func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
///             // Align to every 1/10 the size of the scroll view.
///             target.rect.origin.x = (target.rect.origin.x
///                 / (context.containerSize.width / 10)).rounded()
///                 * (context.containerSize.width / 10)
///         }
///     }
///
/// ### Paging Behavior
///
/// SwiftUI offers built in scroll behaviors. One such behavior
/// is the ``PagingScrollTargetBehavior`` which uses the geometry of the scroll
/// view to decide where to allow scrolls to end.
///
/// In the following example, every view in the lazy stack is flexible
/// in both directions and the scroll view will settle to container aligned
/// boundaries.
///
///     ScrollView {
///         LazyVStack(spacing: 0.0) {
///             ForEach(items) { item in
///                 FullScreenItem(item)
///             }
///         }
///     }
///     .scrollTargetBehavior(.paging)
///
/// ### View Aligned Behavior
///
/// SwiftUI also offers a ``ViewAlignedScrollTargetBehavior`` scroll behavior
/// that will always settle on the geometry of individual views.
///
///     ScrollView(.horizontal) {
///         LazyHStack(spacing: 10.0) {
///             ForEach(items) { item in
///                 ItemView(item)
///             }
///         }
///         .scrollTargetLayout()
///     }
///     .scrollTargetBehavior(.viewAligned)
///
/// You configure which views should be used for settling using the
/// ``View/scrollTargetLayout(isEnabled:)`` modifier. Apply this modifier to a
/// layout container like ``LazyVStack`` or ``HStack`` and each individual
/// view in that layout will be considered for alignment.
///
/// Use types conforming to this protocol with the
/// ``View/scrollTargetBehavior(_:)`` modifier.
public protocol ScrollTargetBehavior {
    /// Updates the proposed target that a scrollable view should scroll to.
    ///
    /// The system calls this method in two main cases:
    /// - When a scroll gesture ends, it calculates where it would naturally
    ///   scroll to using its deceleration rate. The system
    ///   provides this calculated value as the target of this method.
    /// - When a scrollable view's size changes, it calculates where it should
    ///   be scrolled given the new size and provides this calculates value
    ///   as the target of this method.
    ///
    /// You can implement this method to override the calculated target
    /// which will have the scrollable view scroll to a different position
    /// than it would otherwise.
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext)

    /// Properties of this behavior
    func properties(context: PropertiesContext) -> Properties

    /// The context in which a scroll behavior updates the scroll target.
    typealias TargetContext = ScrollTargetBehaviorContext

    /// The properties of a scroll behavior
    typealias Properties = ScrollTargetBehaviorProperties

    /// The properties context of a scroll behavior.
    typealias PropertiesContext = ScrollTargetBehaviorPropertiesContext
}

extension ScrollTargetBehavior {
    /// Properties of this behavior
    public func properties(context: PropertiesContext) -> Properties {
        Properties()
    }
}

/// The context in which a scroll target behavior updates its scroll target.
@dynamicMemberLookup
public struct ScrollTargetBehaviorContext {
    /// The original target when the scroll gesture began.
    public let originalTarget: ScrollTarget

    /// The current velocity of the scrollable view's scroll gesture.
    public let velocity: Vector

    /// The size of the content of the scrollable view.
    public let contentSize: Size

    /// The size of the container of the scrollable view.
    ///
    /// This is the size of the bounds of the scroll view subtracting any
    /// insets applied to the scroll view (like the safe area).
    public let containerSize: Size

    /// The axes in which the scrollable view is scrollable.
    public let axes: Axis.Set

    /// The scroll view's environment.
    let environment: EnvironmentValues

    /// The frames of the views in the scroll view's scroll target layout,
    /// as last placed, in the content's own space — what
    /// `ViewAlignedScrollTargetBehavior` aligns to.
    let targetFrames: [Rect]

    public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
        environment[keyPath: keyPath]
    }
}

/// Properties influencing the scroll view a scroll target behavior
/// applies to.
public struct ScrollTargetBehaviorProperties: Equatable, Sendable {
    /// Creates a default set of properties.
    public init() {}
}

/// The context in which a scroll target behavior can decide its properties.
public struct ScrollTargetBehaviorPropertiesContext {
    /// The environment of the scroll view.
    public let environment: EnvironmentValues

    /// The scrollable axes of the scroll view.
    public let axes: Axis.Set
}

// MARK: - Paging

/// The scroll behavior that aligns scroll targets to container-based
/// geometry.
///
/// In the following example, every view in the lazy stack is flexible
/// in both directions and the scroll view settles to container-aligned
/// boundaries.
///
///     ScrollView {
///         LazyVStack(spacing: 0.0) {
///             ForEach(items) { item in
///                 FullScreenItem(item)
///             }
///         }
///     }
///     .scrollTargetBehavior(.paging)
///
/// A scroll moves at most one page from the one it started on, however
/// hard it is flung; let go of after less than half a page with little
/// speed, it goes back. The last page ends where the content does.
public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    /// Creates a paging scroll behavior.
    public init() {}

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        for (axis, along) in [(Axis.horizontal, Axis.Set.horizontal), (.vertical, .vertical)] where context.axes.contains(along) {
            let page = context.containerSize[axis]
            guard page > 0 else { continue }
            let end = max(0, context.contentSize[axis] - page)
            let startPage = (context.originalTarget.rect.origin[axis] / page).rounded()
            var landing = (target.rect.origin[axis] / page).rounded()
            landing = min(max(landing, startPage - 1), startPage + 1)
            target.rect.origin[axis] = min(max(landing * page, 0), end)
        }
        target.anchor = nil
    }
}

extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    /// The scroll behavior that aligns scroll targets to container-based
    /// geometry.
    ///
    /// In the following example, every view in the lazy stack is flexible
    /// in both directions and the scroll view settles to container-aligned
    /// boundaries.
    ///
    ///     ScrollView {
    ///         LazyVStack(spacing: 0.0) {
    ///             ForEach(items) { item in
    ///                 FullScreenItem(item)
    ///             }
    ///         }
    ///     }
    ///     .scrollTargetBehavior(.paging)
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

// MARK: - View aligned

/// The scroll behavior that aligns scroll targets to view-based geometry.
///
/// You use this behavior when a scroll view should always align its
/// scroll targets to a rectangle that's aligned to the geometry of a view. In
/// the following example, the scroll view always picks an item view
/// to settle on.
///
///     ScrollView(.horizontal) {
///         LazyHStack(spacing: 10.0) {
///             ForEach(items) { item in
///                 ItemView(item)
///             }
///         }
///         .scrollTargetLayout()
///     }
///     .scrollTargetBehavior(.viewAligned)
///     .padding(.horizontal, 20.0)
///
/// You configure which views should be used for settling using the
/// ``View/scrollTargetLayout()`` modifier. Apply this modifier to a
/// layout container like ``LazyVStack`` or ``HStack`` and each individual
/// view in that layout will be considered for alignment.
///
/// A scroll comes to rest with the leading (or top) edge of the view
/// nearest to where it would have ended at the scroll view's leading (or
/// top) edge — or at the content's end, for views that cannot get there.
/// Of a lazy container's views, those built when the scroll ends count.
public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {

    /// A type that defines the amount of views that can be scrolled at a time.
    public struct LimitBehavior: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case automatic, always, alwaysByFew, alwaysByOne, never
        }

        let kind: Kind

        /// The automatic limit behavior.
        ///
        /// By default, the behavior will be limited in compact horizontal
        /// size classes and will not be limited otherwise. There are no size
        /// classes here, so it does not limit.
        public static var automatic: LimitBehavior { LimitBehavior(kind: .automatic) }

        /// The always limit behavior.
        ///
        /// Always limit the amount of views that can be scrolled.
        public static var always: LimitBehavior { LimitBehavior(kind: .always) }

        /// The always-by-few limit behavior.
        ///
        /// Limit the number of views that can be scrolled by a single
        /// interaction to a small number of views, rather than
        /// a single view at a time. The number of views is
        /// determined automatically: as many as the scroll view shows.
        public static var alwaysByFew: LimitBehavior { LimitBehavior(kind: .alwaysByFew) }

        /// The always-by-one limit behavior.
        ///
        /// Limit the number of views that can be scrolled by
        /// a single interaction to a single view.
        public static var alwaysByOne: LimitBehavior { LimitBehavior(kind: .alwaysByOne) }

        /// The never limit behavior.
        ///
        /// Never limit the amount of views that can be scrolled.
        public static var never: LimitBehavior { LimitBehavior(kind: .never) }
    }

    let limitBehavior: LimitBehavior

    /// Creates a view aligned scroll behavior.
    public init(limitBehavior: LimitBehavior = .automatic) {
        self.limitBehavior = limitBehavior
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard !context.targetFrames.isEmpty else { return }
        for (axis, along) in [(Axis.horizontal, Axis.Set.horizontal), (.vertical, .vertical)] where context.axes.contains(along) {
            let end = max(0, context.contentSize[axis] - context.containerSize[axis])
            // Where each view would put the scroll at rest, in order, once
            // each.
            var stops: [Double] = []
            for frame in context.targetFrames {
                stops.append(min(max(frame.origin[axis], 0), end))
            }
            stops.sort()
            stops = stops.reduce(into: []) { kept, stop in
                if let last = kept.last, abs(last - stop) < 0.5 { return }
                kept.append(stop)
            }
            var landing = Self.nearest(to: target.rect.origin[axis], in: stops)
            if let limit = limit(along: axis, context: context) {
                let start = Self.nearest(to: context.originalTarget.rect.origin[axis], in: stops)
                landing = min(max(landing, start - limit), start + limit)
            }
            target.rect.origin[axis] = stops[landing]
        }
        target.anchor = nil
    }

    /// How many views one scroll may move by along `axis`; `nil` for any.
    private func limit(along axis: Axis, context: TargetContext) -> Int? {
        switch limitBehavior.kind {
        case .automatic, .never:
            return nil
        case .always, .alwaysByOne:
            return 1
        case .alwaysByFew:
            let extents = context.targetFrames.map { $0.size[axis] }
            let average = extents.reduce(0, +) / Double(extents.count)
            guard average > 0 else { return 1 }
            return max(1, Int((context.containerSize[axis] / average).rounded(.down)))
        }
    }

    /// The index of the stop closest to `offset`.
    private static func nearest(to offset: Double, in stops: [Double]) -> Int {
        var best = 0
        for index in stops.indices where abs(stops[index] - offset) < abs(stops[best] - offset) {
            best = index
        }
        return best
    }
}

extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    /// The scroll behavior that aligns scroll targets to view-based geometry.
    ///
    /// You use this behavior when a scroll view should always align its
    /// scroll targets to a rectangle that's aligned to the geometry of a view. In
    /// the following example, the scroll view always picks an item view
    /// to settle on.
    ///
    ///     ScrollView(.horizontal) {
    ///         LazyHStack(spacing: 10.0) {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///         .scrollTargetLayout()
    ///     }
    ///     .scrollTargetBehavior(.viewAligned)
    ///     .padding(.horizontal, 20.0)
    ///
    /// You configure which views should be used for settling using the
    /// ``View/scrollTargetLayout()`` modifier. Apply this modifier to a
    /// layout container like ``LazyHStack`` or ``HStack`` and each individual
    /// view in that layout will be considered for alignment.
    public static var viewAligned: ViewAlignedScrollTargetBehavior { ViewAlignedScrollTargetBehavior() }

    /// The scroll behavior that aligns scroll targets to view-based geometry,
    /// limiting how many views a scroll moves by.
    public static func viewAligned(limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior) -> Self {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }
}

// MARK: - Any

/// A type-erased scroll target behavior — for picking one of several at run
/// time:
///
///     .scrollTargetBehavior(isPaged
///         ? AnyScrollTargetBehavior(.paging)
///         : AnyScrollTargetBehavior(.viewAligned))
///
/// It keeps the behavior's two methods, made for its type when it is
/// wrapped.
public struct AnyScrollTargetBehavior: ScrollTargetBehavior {
    private let update: (inout ScrollTarget, ScrollTargetBehaviorContext) -> Void
    private let decideProperties: (ScrollTargetBehaviorPropertiesContext) -> ScrollTargetBehaviorProperties

    /// Creates a new type-erased scroll target behavior.
    public init(_ base: some ScrollTargetBehavior) {
        update = base.updateTarget
        decideProperties = base.properties
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        update(&target, context)
    }

    public func properties(context: PropertiesContext) -> Properties {
        decideProperties(context)
    }
}

// MARK: - In the environment

/// The scroll target behavior a `ScrollView` below applies: the behavior's
/// method, made for its type where `.scrollTargetBehavior` was applied.
struct ScrollTargetBehaviorEntry {
    let updateTarget: (inout ScrollTarget, ScrollTargetBehaviorContext) -> Void

    init<B: ScrollTargetBehavior>(_ behavior: B) {
        updateTarget = behavior.updateTarget
    }
}

private struct ScrollTargetBehaviorKey: EnvironmentKey {
    static var defaultValue: ScrollTargetBehaviorEntry? { nil }
}

extension EnvironmentValues {
    /// The scroll target behavior set by `.scrollTargetBehavior`, if any.
    var scrollTargetBehavior: ScrollTargetBehaviorEntry? {
        get { self[ScrollTargetBehaviorKey.self] }
        set { self[ScrollTargetBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Sets the scroll behavior of views scrollable in the provided axes.
    ///
    /// A scrollable view calculates where scroll gestures should end using its
    /// deceleration rate and the state of its scroll gesture by default. A
    /// scroll behavior allows for customizing this logic. You can provide
    /// your own ``ScrollTargetBehavior`` or use one of the built in behaviors
    /// provided by SwiftUI.
    ///
    /// ### Paging Behavior
    ///
    /// SwiftUI offers a ``PagingScrollTargetBehavior`` behavior which uses the
    /// geometry of the scroll view to decide where to allow scrolls to end.
    ///
    /// In the following example, every view in the lazy stack is flexible
    /// in both directions and the scroll view will settle to container aligned
    /// boundaries.
    ///
    ///     ScrollView {
    ///         LazyVStack(spacing: 0.0) {
    ///             ForEach(items) { item in
    ///                 FullScreenItem(item)
    ///             }
    ///         }
    ///     }
    ///     .scrollTargetBehavior(.paging)
    ///
    /// ### View Aligned Behavior
    ///
    /// SwiftUI offers a ``ViewAlignedScrollTargetBehavior`` scroll behavior
    /// that will always settle on the geometry of individual views.
    ///
    ///     ScrollView(.horizontal) {
    ///         LazyHStack(spacing: 10.0) {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///         .scrollTargetLayout()
    ///     }
    ///     .scrollTargetBehavior(.viewAligned)
    ///
    /// You configure which views should be used for settling using the
    /// ``View/scrollTargetLayout(isEnabled:)`` modifier. Apply this modifier to
    /// a layout container like ``LazyVStack`` or ``HStack`` and each individual
    /// view in that layout will be considered for alignment.
    public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        _ModifierView(content: self, modifier: ScrollTargetBehaviorModifier(behavior: behavior))
    }
}

/// `.scrollTargetBehavior(_:)`. The same behavior applied again — equal
/// fields, the built-in ones always — writes nothing new.
struct ScrollTargetBehaviorModifier<Behavior: ScrollTargetBehavior>: PrimitiveModifier {
    let behavior: Behavior

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.scrollTargetBehavior = ScrollTargetBehaviorEntry(behavior)
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }

    func _isEquivalent(to other: ScrollTargetBehaviorModifier<Behavior>) -> Bool {
        _areEquivalent(behavior, other.behavior)
    }
}
