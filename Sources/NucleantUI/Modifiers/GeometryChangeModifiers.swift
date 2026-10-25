//
//  GeometryChangeModifiers.swift
//  NucleantUI
//
//  `.onGeometryChange`: a value worked out from where the view was placed,
//  and an action run when it comes out different. Each placement of the
//  view asks the transform again — a scroll that moves it, a window that
//  resizes it — and the value is kept by the pass's effects under the
//  view's structural identity, as `.onChange` keeps its own. The action is
//  queued like an `onAppear`, run once the pass is placed; one that writes
//  state marks the next frame.
//

extension View {

    /// Adds an action to be performed when a value, created from a
    /// geometry proxy, changes.
    ///
    /// The geometry of a view can change frequently, especially if
    /// the view is contained within a ``ScrollView`` and that scroll view
    /// is scrolling.
    ///
    /// You should avoid updating large parts of your app whenever
    /// the scroll geometry changes. To aid in this, you provide two
    /// closures to this modifier:
    ///   * transform: This converts a value of ``GeometryProxy`` to your
    ///     own data type.
    ///   * action: This provides the data type you created in `of`
    ///     and is called whenever the data type changes.
    ///
    /// For example, you can use this modifier to know how much of a view
    /// is visible on screen. In the following example,
    /// the data type you convert to is a `Bool` and the action is called
    /// whenever the `Bool` changes.
    ///
    /// ```swift
    /// VideoPlayer(video)
    ///     .onGeometryChange(for: Bool.self) { proxy in
    ///         let frame = proxy.frame(in: .scrollView)
    ///         let bounds = proxy.bounds(of: .scrollView) ?? .zero
    ///         let visible = frame.intersection(Rect(origin: .zero, size: bounds.size))
    ///         return visible.height / frame.height > 0.75
    ///     } action: { isVisible in
    ///         video.updateAutoplayingState(isVisible: isVisible)
    ///     }
    /// ```
    ///
    /// The action also runs the first time the view is placed, with the
    /// value it is placed with.
    ///
    /// - Parameters:
    ///   - type: The type of value transformed from a ``GeometryProxy``.
    ///   - transform: A closure that transforms a ``GeometryProxy``
    ///     to your type.
    ///   - action: A closure to run when the transformed data changes.
    ///   - newValue: The new value that failed the comparison check.
    public func onGeometryChange<T: Equatable & Sendable>(
        for type: T.Type,
        of transform: @escaping @Sendable (GeometryProxy) -> T,
        action: @escaping @MainActor (_ newValue: T) -> Void
    ) -> some View {
        _ModifierView(content: self) { context in
            GeometryChangeContent(
                key: StateKey(path: context.path, propertyIndex: -1, viewType: ObjectIdentifier(GeometryChangeMarker.self)),
                effects: context.effects,
                transform: transform,
                action: action
            )
        }
    }

    /// Adds an action to be performed when a value, created from a
    /// geometry proxy, changes.
    ///
    /// The geometry of a view can change frequently, especially if
    /// the view is contained within a ``ScrollView`` and that scroll view
    /// is scrolling.
    ///
    /// You should avoid updating large parts of your app whenever
    /// the scroll geometry changes. To aid in this, you provide two
    /// closures to this modifier:
    ///   * transform: This converts a value of ``GeometryProxy`` to your
    ///     own data type.
    ///   * action: This provides the data type you created in `of`
    ///     and is called whenever the data type changes.
    ///
    /// The action also runs the first time the view is placed, with the
    /// value it is placed with as both the old and the new value.
    ///
    /// - Parameters:
    ///   - type: The type of value transformed from a geometry proxy.
    ///   - transform: A closure that transforms a ``GeometryProxy``
    ///     to your type.
    ///   - action: A closure to run when the transformed data changes.
    ///   - oldValue: The old value that failed the comparison check.
    ///   - newValue: The new value that failed the comparison check.
    public func onGeometryChange<T: Equatable & Sendable>(
        for type: T.Type,
        of transform: @escaping @Sendable (GeometryProxy) -> T,
        action: @escaping @MainActor (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        _ModifierView(content: self) { context in
            GeometryTransitionContent(
                key: StateKey(path: context.path, propertyIndex: -1, viewType: ObjectIdentifier(GeometryTransitionMarker.self)),
                effects: context.effects,
                transform: transform,
                action: action
            )
        }
    }
}

/// `.onGeometryChange(for:of:action:)` with an action of the new value:
/// asks the transform each time it is placed, and hands the effects the
/// answer.
struct GeometryChangeContent<T: Equatable>: NodeContent {
    let key: StateKey
    let effects: EffectQueue
    let transform: (GeometryProxy) -> T
    let action: @MainActor (T) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        // Drawn where it stood — on its way out, or in a drag's snapshot —
        // is not a new place.
        if !context.freezesMotion {
            let placed = PlacedGeometry(rect: rect, transform: context.transform, spaces: context.coordinateSpaces)
            effects.onGeometryChange(key, to: transform(GeometryProxy(geometry: placed, log: nil)), action)
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}

/// `.onGeometryChange(for:of:action:)` with an action of the old and the
/// new value.
struct GeometryTransitionContent<T: Equatable>: NodeContent {
    let key: StateKey
    let effects: EffectQueue
    let transform: (GeometryProxy) -> T
    let action: @MainActor (T, T) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        if !context.freezesMotion {
            let placed = PlacedGeometry(rect: rect, transform: context.transform, spaces: context.coordinateSpaces)
            effects.onGeometryTransition(key, to: transform(GeometryProxy(geometry: placed, log: nil)), action)
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}

/// Stand in for a view type in the keys, as `OnChangeMarker` does.
private enum GeometryChangeMarker {}
private enum GeometryTransitionMarker {}
