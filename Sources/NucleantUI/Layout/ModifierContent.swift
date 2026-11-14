//
//  ModifierContent.swift
//  NucleantUI
//
//  One node per modifier. Each wraps a single child (`node.singleChild`) and
//  changes either the box it gets, the context it draws under, or both.
//

/// `.frame(width:height:)` and `.frame(minWidth:…)`.
struct FrameContent: NodeContent {
    let width: Double?
    let height: Double?
    let minWidth: Double?
    let maxWidth: Double?
    let minHeight: Double?
    let maxHeight: Double?
    let alignment: Alignment

    /// A frame with a hard extent on an axis is immovable there — the stack
    /// must size it before anything that can stretch. On an axis it says
    /// nothing about, the child decides.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        let fixed = axis == .horizontal ? width : height
        if fixed != nil { return .fixed }
        let maximum = axis == .horizontal ? maxWidth : maxHeight
        if maximum == .infinity { return .flexible }
        let minimum = axis == .horizontal ? minWidth : minHeight
        if maximum != nil || minimum != nil { return .content }
        return node.singleChild?.flexibility(along: axis) ?? .content
    }

    /// The proposal handed inward, the box this node reports outward, and the
    /// inner proposal itself — placement needs that last one so the child is
    /// positioned under the same proposal it was sized by.
    private func resolve(
        _ proposal: ProposedSize,
        childSize: (ProposedSize) -> Size
    ) -> (own: Size, child: Size, inner: ProposedSize) {
        var inner = proposal
        if let width { inner.width = width }
        if let height { inner.height = height }
        // An infinite maximum means "as much as offered", so the child is
        // proposed the container's extent rather than infinity itself.
        if let maxWidth, maxWidth != .infinity {
            inner.width = min(inner.width ?? maxWidth, maxWidth)
        }
        if let maxHeight, maxHeight != .infinity {
            inner.height = min(inner.height ?? maxHeight, maxHeight)
        }
        // A minimum only raises an extent that was offered. With none, the
        // child is asked for its own size and the minimum is applied to
        // the result below — so a `minWidth: 160` panel grows to its
        // widest row instead of wrapping every row at 160.
        if let minWidth, let offered = inner.width { inner.width = max(offered, minWidth) }
        if let minHeight, let offered = inner.height { inner.height = max(offered, minHeight) }

        let child = childSize(inner)

        var own = child
        if let width { own.width = width }
        if let height { own.height = height }
        if let minWidth { own.width = max(own.width, minWidth) }
        if let minHeight { own.height = max(own.height, minHeight) }
        if let maxWidth {
            own.width = maxWidth == .infinity
                ? max(own.width, proposal.width ?? own.width)
                : min(own.width, maxWidth)
        }
        if let maxHeight {
            own.height = maxHeight == .infinity
                ? max(own.height, proposal.height ?? own.height)
                : min(own.height, maxHeight)
        }
        return (own, child, inner)
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        resolve(proposal) { inner in
            node.singleChild?.sizeThatFits(inner) ?? inner.replacingUnspecifiedDimensions()
        }.own
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        // Resolve against the proposal that produced `rect` — re-deriving one
        // from `rect.size` re-applies any proposal-dependent sizing below.
        let sizes = resolve(proposal) { inner in child.sizeThatFits(inner) }
        child.place(
            in: alignment.position(sizes.child, in: rect),
            proposal: sizes.inner,
            context: context,
            into: &list
        )
    }
}

/// `.relativeSize(width:height:)` — an extent given as a fraction of what the
/// parent offered, rather than an absolute number.
///
/// SwiftUI expresses this with `GeometryReader`, which needs the child to be
/// *built* once its size is known — the tree here is built before layout runs,
/// so that is a larger change (it is on the Later list). A fraction covers the
/// common case a `GeometryReader` is usually reached for: a bar or fill sized
/// against its container.
struct RelativeSizeContent: NodeContent {
    let widthFraction: Double?
    let heightFraction: Double?

    private func resolve(_ proposal: ProposedSize) -> ProposedSize {
        var inner = proposal
        if let widthFraction, let width = proposal.width {
            inner.width = max(0, width * widthFraction)
        }
        if let heightFraction, let height = proposal.height {
            inner.height = max(0, height * heightFraction)
        }
        return inner
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        let inner = resolve(proposal)
        guard let child = node.singleChild else {
            return inner.replacingUnspecifiedDimensions()
        }
        var size = child.sizeThatFits(inner)
        // The fraction is the claim, not the child's own preference — a
        // capsule asked for 40% of the width reports 40%, even if it would
        // happily have taken everything.
        if let width = inner.width { size.width = width }
        if let height = inner.height { size.height = height }
        return size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        // `rect` is already the fraction of the parent — the child fills it,
        // and is proposed exactly that, never the fraction a second time.
        node.singleChild?.place(
            in: rect,
            proposal: ProposedSize(rect.size),
            context: context,
            into: &list
        )
    }
}

/// `.padding(_:)`.
struct PaddingContent: NodeContent {
    let insets: EdgeInsets

    private func shrink(_ proposal: ProposedSize) -> ProposedSize {
        ProposedSize(
            width: proposal.width.map { max(0, $0 - insets.horizontal) },
            height: proposal.height.map { max(0, $0 - insets.vertical) }
        )
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        let inner = node.singleChild?.sizeThatFits(shrink(proposal))
            ?? shrink(proposal).replacingUnspecifiedDimensions()
        return Size(
            width: inner.width + insets.horizontal,
            height: inner.height + insets.vertical
        )
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let inner = rect.insetBy(insets)
        node.singleChild?.place(
            in: inner,
            proposal: shrink(proposal),
            context: context,
            into: &list
        )
    }
}

/// `.background(_:)` and `.overlay(_:)` — two children, painted either side of
/// each other. The *content* sizes the node; the decoration is stretched to it.
/// What the two share; each places them in its own order.
protocol DecorationLayout: NodeContent {
    var alignment: Alignment { get }
}

extension DecorationLayout {
    /// Index into `node.children` — never `layoutChildren`, because the two
    /// slots are positional and flattening would merge a multi-child group.
    func content(_ node: ViewNode) -> ViewNode? { node.children.first }
    func decoration(_ node: ViewNode) -> ViewNode? {
        node.children.count > 1 ? node.children[1] : nil
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        content(node)?.sizeThatFits(proposal) ?? proposal.replacingUnspecifiedDimensions()
    }

    /// The decoration, stretched to the content's box: the box is what it
    /// is offered.
    func placeDecoration(of node: ViewNode, in rect: Rect, context: DrawContext, into list: inout DisplayList) {
        guard let decorationNode = decoration(node) else { return }
        let proposal = ProposedSize(rect.size)
        let size = decorationNode.sizeThatFits(proposal)
        decorationNode.place(in: alignment.position(size, in: rect), proposal: proposal, context: context, into: &list)
    }
}

/// `.background(_:)`: the decoration painted first, behind the content.
struct BackgroundContent: DecorationLayout {
    let alignment: Alignment

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        placeDecoration(of: node, in: rect, context: context, into: &list)
        content(node)?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}

/// `.overlay(_:)`: the decoration painted last, over the content.
struct OverlayContent: DecorationLayout {
    let alignment: Alignment

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        content(node)?.place(in: rect, proposal: proposal, context: context, into: &list)
        placeDecoration(of: node, in: rect, context: context, into: &list)
    }
}

/// `.opacity(_:)`.
struct OpacityContent: NodeContent {
    let opacity: AnimatableDataState<Double>

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        inner.opacity *= min(max(opacity.current(), 0), 1)
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

/// `.hidden()` — laid out exactly as before, painted not at all.
struct HiddenContent: NodeContent {
    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        // Still placed, so `frame` is set and layout is unchanged; the child's
        // commands are simply thrown away — a drawing group's included, which
        // would otherwise composite a node the view says is hidden.
        var discarded = DisplayList()
        var inner = context
        inner.flattensRenderNodes = true
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &discarded)
    }
}

/// `.offset` — moves the drawing without changing the layout.
///
/// A translation on the transform the child is drawn under, as SwiftUI's
/// offset is a geometry effect: the child is placed in the rect layout
/// gave, so nothing under it sees its rect change — an offset animating
/// never reads as a move of layout to whatever is placed inside it — and
/// what reads the transform (drawing, hit testing, a `GeometryReader`'s
/// frame in the window) sees the view where it is drawn. The amount is
/// animated, filed by path like an opacity: a change under an animation
/// moves the view from where it is showing, and a transition built from
/// an offset has its `willAppear` amount to start from.
struct OffsetContent: NodeContent {
    /// x and y, animated.
    let offset: AnimatableDataState<AnimatablePair<Double, Double>>

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let xy = offset.current()
        var inner = context
        if xy.first != 0 || xy.second != 0 {
            inner.transform = context.transform.concatenating(.translation(x: xy.first, y: xy.second))
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

/// `.position(x:y:)` — the child's center pinned to a point in this node's
/// own space. The node takes everything it is offered, so that space is the
/// parent's; the child is offered the same and keeps its own size.
struct PositionContent: NodeContent {
    let position: Point

    /// Like a `Color`, it fills what it is given.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        .flexible
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        // An axis with no finite extent offered has nothing to fill: there
        // the node is as big as the child.
        func finite(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite ? $0 : nil }
        }
        let width = finite(proposal.width)
        let height = finite(proposal.height)
        if let width, let height { return Size(width: width, height: height) }
        let child = node.singleChild?.sizeThatFits(proposal) ?? .zero
        return Size(width: width ?? child.width, height: height ?? child.height)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        let inner = ProposedSize(rect.size)
        let size = child.sizeThatFits(inner)
        child.place(
            in: Rect(
                x: rect.minX + position.x - size.width / 2,
                y: rect.minY + position.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            proposal: inner,
            context: context,
            into: &list
        )
    }
}

/// `.rotationEffect(_:anchor:)` — a rotation about an anchor inside the
/// node's own rect, with no effect on layout.
struct RotationContent: NodeContent {
    /// The angle, in radians, animated.
    let radians: AnimatableDataState<Double>
    let anchor: UnitPoint

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        inner.transform = context.transform
            .concatenating(.around(anchor.resolved(in: rect), .rotation(.radians(radians.current()))))
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

/// `.scaleEffect(x:y:anchor:)` — a scale about an anchor inside the node's
/// own rect, with no effect on layout.
struct ScaleContent: NodeContent {
    /// The factors, (x, y), animated.
    let factors: AnimatableDataState<AnimatablePair<Double, Double>>
    let anchor: UnitPoint

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let xy = factors.current()
        var inner = context
        inner.transform = context.transform
            .concatenating(.around(anchor.resolved(in: rect), .scale(x: xy.first, y: xy.second)))
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

/// `.clipped()` / `.cornerRadius(_:)`'s clipping half.
struct ClipContent: NodeContent {
    let cornerRadius: Double

    var clipsChildren: Bool { true }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        // Cut to the frame as shown — mid-animation, the size in between —
        // while the child is laid out at the layout's own.
        node.singleChild?.place(
            in: rect,
            proposal: proposal,
            context: context.clipped(to: node.frame, cornerRadius: cornerRadius),
            into: &list
        )
    }
}

/// `._parked(true)` — a subtree kept in the tree but taken off screen:
/// zero size, never placed, so nothing under it is drawn, hit tested or
/// given a GPU slot. Its views keep their identity and state, which is what
/// a `NavigationStack` wants for the screens under the top one.
struct ParkedContent: NodeContent {
    let isParked: Bool

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        guard isParked else {
            return node.singleChild?.sizeThatFits(proposal) ?? proposal.replacingUnspecifiedDimensions()
        }
        return .zero
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard !isParked else { return }
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}

/// `.onTapGesture` and `Button`'s pointer handling.
struct InteractionContent: NodeContent {
    let target: HitTarget

    var hitTarget: HitTarget? { target }
}

/// `.environment(...)` and the sugar built on it (`.font`, `.foregroundStyle`,
/// `.colorScheme`): a build-time concern only. By placement time the values
/// are in the leaves — a style was resolved where its view was built, in the
/// environment it read — so the node places its child as it is.
struct EnvironmentContent: NodeContent {
    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}
