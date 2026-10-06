//
//  FramedModifier.swift
//  NucleantUI
//
//  `.framed(_:)`: a view given a whole `Rect` in its parent's space — the
//  size `.frame(width:height:)` gives and the place `.position(_:)` gives,
//  as one modifier and one node.
//

// MARK: - Framed

extension View {
    /// Lays this view out in `rect`, measured in its parent's coordinate
    /// space — what `.frame(width: rect.width, height: rect.height)` and then
    /// `.position(x: rect.midX, y: rect.midY)` do, in one modifier.
    ///
    /// The view inside is offered `rect`'s size and placed in it by
    /// `alignment`, as in a frame. The result takes all the space its parent
    /// offers — it is the space `rect` is measured in.
    public func framed(_ rect: Rect, alignment: Alignment = .center) -> some View {
        _ModifierView(content: self, key: ["framed", rect, alignment] as [AnyHashable]) { _ in
            FramedContent(rect: rect, alignment: alignment)
        }
    }
}

/// `.framed(_:)` — the child offered `rect`'s size and aligned in `rect`,
/// which is measured in this node's own space. The node takes everything it
/// is offered, so that space is the parent's.
struct FramedContent: NodeContent {
    let rect: Rect
    let alignment: Alignment

    /// Like a `Color`, it fills what it is given.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        .flexible
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        // An axis with no finite extent offered has nothing to fill: there
        // the node is as big as the frame.
        func finite(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite ? $0 : nil }
        }
        return Size(
            width: finite(proposal.width) ?? rect.width,
            height: finite(proposal.height) ?? rect.height
        )
    }

    func place(node: ViewNode, in bounds: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        let frame = Rect(origin: bounds.origin + rect.origin, size: rect.size)
        // A frame's exact extent, so the child sizes itself against it.
        let inner = ProposedSize(rect.size)
        let size = child.sizeThatFits(inner)
        child.place(
            in: alignment.position(size, in: frame),
            proposal: inner,
            context: context,
            into: &list
        )
    }
}
