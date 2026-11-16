//
//  IdentityModifier.swift
//  NucleantUI
//
//  `.id(_:)`: a view whose identity is a value. Its content stands in a slot
//  of its own for each id, as a `ForEach` row does for its element: a new
//  id is a new view — its state starts over, the old one goes out with its
//  transition and the new one comes in with its own. Its node knows the id,
//  for scrolling to the view by it (`ScrollViewReader`).
//

extension View {
    /// Binds a view's identity to the given proxy value.
    ///
    /// When the proxy value specified by the `id` parameter changes, the
    /// identity of the view — for example, its state — is reset.
    public func id<ID: Hashable>(_ id: ID) -> some View {
        _IdentifiedView(content: self, id: id)
    }
}

/// A view `.id(_:)` gave an identity.
@View
public struct _IdentifiedView<Content: View, ID: Hashable> {
    let content: Content
    let id: ID

    init(content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    public var body: Never { bodyUnavailable() }
}

extension _IdentifiedView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let slots = context.rowSlots(for: ID.self)
        let index = slots.slot(for: id)
        let isNew = context.isNewChild(at: index)
        let node = context.child(index) { ctx in buildNode(content, &ctx) }
        slots.forgetGone(from: context.position, built: 1)
        // The view an old id stood for leaves with its transition, the new
        // one arrives with its own.
        return ContentNode(
            content: IdentifiedContent(id: id, view: node),
            children: context.transitionChildren([(index: index, node: node, isNew: isNew)])
        )
    }
}

/// `.id(_:)`'s node: what it identifies dissolves into the layout around
/// it, as a group's children do, and it knows the id.
struct IdentifiedContent<ID: Hashable>: NodeContent {
    let id: ID
    /// The node of the view it identifies — inside any transition slot
    /// standing over it.
    let view: ViewNode

    var isTransparent: Bool { true }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        // Only reached as the root or the sole child of a modifier. One
        // view arriving while another leaves is sized as a ZStack would be.
        let children = node.layoutChildren
        guard !children.isEmpty else { return .zero }
        var result = Size.zero
        for child in children {
            let size = child.sizeThatFits(proposal)
            result.width = max(result.width, size.width)
            result.height = max(result.height, size.height)
        }
        return result
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        for child in node.layoutChildren {
            child.place(in: rect, proposal: proposal, context: context, into: &list)
        }
    }
}

extension IdentifiedContent { static var placesPurely: Bool { true } }
