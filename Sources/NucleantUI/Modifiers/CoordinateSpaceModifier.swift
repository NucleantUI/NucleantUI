//
//  CoordinateSpaceModifier.swift
//  NucleantUI
//
//  `.coordinateSpace(_:)`: a view's own space given a name. The name only
//  means something once the view is placed, so it is the placement that
//  publishes it — the rect and transform the view was placed with, handed
//  down to its subtree in the `DrawContext` — for a `GeometryProxy` below
//  to measure against.
//

extension View {

    /// Assigns a name to the view's coordinate space, so other code can operate
    /// on dimensions like points and sizes relative to the named space.
    ///
    /// Use `coordinateSpace(_:)` to allow another function to find and
    /// operate on a view and operate on dimensions relative to that view.
    ///
    /// ```swift
    /// ScrollView {
    ///     VStack {
    ///         ForEach(steps) { step in
    ///             StepRow(step)
    ///                 .onGeometryChange(for: Double.self) { proxy in
    ///                     proxy.frame(in: .named("recipe")).minY
    ///                 } action: { top in
    ///                     model.noteTop(top, of: step)
    ///                 }
    ///         }
    ///     }
    ///     .coordinateSpace(.named("recipe"))
    /// }
    /// ```
    ///
    /// - Parameter name: A name used to identify this coordinate space.
    public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View {
        _ModifierView(content: self, key: ["coordinateSpace", name.name] as [AnyHashable]) { _ in
            CoordinateSpaceContent(name: name.name)
        }
    }
}

/// Places its child as it is, under a context that knows this node's rect
/// by `name`.
struct CoordinateSpaceContent: NodeContent {
    let name: AnyHashable

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        inner.coordinateSpaces.append(CoordinateSpaceFrame(name: name, rect: rect, transform: context.transform))
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}
