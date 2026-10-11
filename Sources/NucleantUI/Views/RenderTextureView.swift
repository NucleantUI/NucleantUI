//
//  RenderTextureView.swift
//  NucleantUI
//
//  `tex.view()` — a `RenderTexture` shown in the tree.
//
//  The texture's image is composited into the view's frame, the way a
//  `.drawingGroup()`'s node is: nothing is drawn into the enclosing canvas,
//  and the image is borrowed rather than owned — several placements of one
//  texture all point at it.
//

/// A `RenderTexture` as a view. Made by `RenderTexture.view()`.
@View
public struct RenderTextureView {
    let texture: RenderTexture
    var isResizable = false

    init(texture: RenderTexture, _viewID: ViewID) {
        self.texture = texture
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }

    /// Stretched to whatever it is offered instead of drawn at the texture's
    /// own size — `Image.resizable()`'s rule, and composited by the same GPU
    /// draw either way, so scaling costs nothing extra.
    public func resizable() -> RenderTextureView {
        var copy = self
        copy.isResizable = true
        return copy
    }
}

extension RenderTextureView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        ViewNode(content: RenderTextureContent(
            key: RenderNodeKey(path: context.path, identity: context.viewIdentity),
            texture: texture,
            isResizable: isResizable
        ))
    }
}

/// Reserves the placement container at `place` and points it at the frame.
/// Emits no draw commands: the pixels arrive through the engine, not the
/// canvas.
struct RenderTextureContent: NodeContent {
    let key: RenderNodeKey
    let texture: RenderTexture
    let isResizable: Bool

    /// Fixed at the texture's size; resizable, it takes what it is offered
    /// and the texture's size on an axis nobody constrained.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        isResizable ? .flexible : .fixed
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        isResizable ? proposal.replacingUnspecifiedDimensions(by: texture.size) : texture.size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0, let host = ShaderHost.current else { return }
        let clip = context.compositeClip
        host.renderTextures.place(key: key, texture: texture, rect: rect, clip: clip)
        host.boundaries.noteNested(at: list.commands.count, rect: clip.map { rect.intersection($0) } ?? rect)
    }
}
