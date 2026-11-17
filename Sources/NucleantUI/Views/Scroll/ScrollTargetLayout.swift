//
//  ScrollTargetLayout.swift
//  NucleantUI
//
//  `.scrollTargetLayout()`: the views of one layout are where a scroll may
//  come to rest. Placed, it tells the scroll view around it where its
//  layout's views landed; the scroll view keeps them, in its content's own
//  space, for its target behavior (`ViewAlignedScrollTargetBehavior`).
//

extension View {
    /// Configures the outermost layout as a scroll target layout.
    ///
    /// This modifier works together with the
    /// ``ViewAlignedScrollTargetBehavior`` to ensure that scroll views align
    /// to view based content.
    ///
    /// Apply this modifier to layout containers like ``LazyHStack`` or
    /// ``VStack`` within a ``ScrollView`` that contain the main repeating
    /// content of your ``ScrollView``.
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
    /// A scroll target layout will ensure that any target layout
    /// nested within the primary one will not also become a scroll
    /// target layout.
    ///
    ///     LazyHStack { // a scroll target layout
    ///         VStack { ... } // not a scroll target layout
    ///         LazyHStack { ... } // also not a scroll target layout
    ///     }
    ///     .scrollTargetLayout()
    public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        _ModifierView(content: self, modifier: ScrollTargetLayoutModifier(isEnabled: isEnabled))
    }
}

struct ScrollTargetLayoutModifier: PrimitiveModifier, Equatable {
    let isEnabled: Bool

    func makeContent(_ context: inout BuildContext) -> ScrollTargetLayoutContent {
        ScrollTargetLayoutContent(isEnabled: isEnabled)
    }
}

/// Places the layout it wraps, then hands the scroll view around it the
/// frames of the layout's views. Placed every pass — what it reports is
/// where they are now — though what is inside may be kept.
struct ScrollTargetLayoutContent: NodeContent {
    let isEnabled: Bool

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        guard isEnabled, let scroller = context.enclosingScroller else {
            child.place(in: rect, proposal: proposal, context: context, into: &list)
            return
        }
        // A target layout inside this one is not one.
        var inner = context
        inner.enclosingScroller = nil
        child.place(in: rect, proposal: proposal, context: inner, into: &list)
        scroller.addTargets(Self.targetViews(of: child))
    }

    /// The views of the layout `node` is or wraps: down through the
    /// modifiers over it to the first node with other than one view in its
    /// layout. Runs a lazy container skipped stand for are not views.
    private static func targetViews(of node: ViewNode) -> [ViewNode] {
        var layout = node
        while true {
            let inner = layout.layoutChildren
            guard inner.count == 1 else {
                return inner.filter { $0.content(as: LazyGapContent.self) == nil }
            }
            layout = inner[0]
        }
    }
}
