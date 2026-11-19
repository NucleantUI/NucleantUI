//
//  IgnoresSafeArea.swift
//  NucleantUI
//
//  `.ignoresSafeArea`: a view laid out as if the safe area of some regions
//  weren't there, at some edges. It takes the size it would take anyway;
//  where its frame is on the safe area's edge, what it wraps is offered as
//  much more as there is out to the window's edge, and placed out into it.
//

extension View {
    /// Expands the safe area of a view.
    ///
    /// By default, the layout system sizes and positions views to avoid
    /// certain safe areas. This ensures that system content like the
    /// software keyboard doesn't obstruct your views. To extend your content
    /// into these regions, you can ignore safe areas on specific edges by
    /// applying this modifier.
    ///
    ///     ZStack {
    ///         LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom)
    ///             .ignoresSafeArea(.keyboard)
    ///         MessageList()
    ///     }
    ///
    /// - Parameters:
    ///   - regions: The regions to expand the view's safe area into. The
    ///     modifier expands into all safe area region types by default.
    ///   - edges: The set of edges to expand. Any edges that you
    ///     don't include in this set remain unchanged. The set includes all
    ///     edges by default.
    ///
    /// - Returns: A view with an expanded safe area.
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View {
        _ModifierView(content: self, modifier: IgnoresSafeAreaModifier(regions: regions, edges: edges))
    }
}

struct IgnoresSafeAreaModifier: PrimitiveModifier, Equatable {
    let regions: SafeAreaRegions
    let edges: Edge.Set

    func makeContent(_ context: inout BuildContext) -> IgnoresSafeAreaContent {
        IgnoresSafeAreaContent(regions: regions, edges: edges)
    }
}

/// Sized as what it wraps; placed out into the safe area it touches. How far
/// it reaches depends on where in the window it is as well as on its rect
/// and context, so a kept placement under a safe area is never drawn again
/// moved (`PlacementRecord.likeness`).
struct IgnoresSafeAreaContent: NodeContent {
    let regions: SafeAreaRegions
    let edges: Edge.Set

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        node.singleChild?.sizeThatFits(proposal) ?? proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        let reach = context.safeArea.insets(of: regions, at: rect)
        let top = edges.contains(.top) ? reach.top : 0
        let leading = edges.contains(.leading) ? reach.leading : 0
        let bottom = edges.contains(.bottom) ? reach.bottom : 0
        let trailing = edges.contains(.trailing) ? reach.trailing : 0
        guard top != 0 || leading != 0 || bottom != 0 || trailing != 0 else {
            child.place(in: rect, proposal: proposal, context: context, into: &list)
            return
        }
        // Offered as much more as it can reach, and placed from the corner
        // that far out: a view that takes what it is offered fills it, one
        // that doesn't moves out with its top-leading corner.
        let grown = ProposedSize(
            width: proposal.width.map { max(0, $0 + leading + trailing) },
            height: proposal.height.map { max(0, $0 + top + bottom) }
        )
        let size = child.sizeThatFits(grown)
        child.place(
            in: Rect(x: rect.minX - leading, y: rect.minY - top, width: size.width, height: size.height),
            proposal: grown,
            context: context,
            into: &list
        )
    }
}
