//
//  RenderTextureShaderView.swift
//  NucleantUI
//
//  `tex.shader(fx)` — a shader run over a `RenderTexture`'s pixels.
//
//  `.shader(_:)` on a view draws that view into a canvas and samples the
//  canvas. A texture *is* already that canvas, so there is no layer to make
//  and nothing to draw: the slot binds the texture's own image as its content
//  and the effect reads it with `layer(uv)`, exactly as it would read a view.
//  An effect is therefore the same function either way — which is the point of
//  spelling it the same way.
//

/// A `RenderTexture` with a shader over it. Made by `RenderTexture.shader(_:)`.
@View
public struct RenderTextureShaderView {
    let texture: RenderTexture
    let function: ShaderFunction
    let arguments: [ShaderArgument]
    let textures: [ShaderTextureInput]
    let draw: ShaderDraw
    var isResizable = false

    init(
        texture: RenderTexture,
        function: ShaderFunction,
        arguments: [ShaderArgument],
        textures: [ShaderTextureInput],
        draw: ShaderDraw,
        _viewID: ViewID
    ) {
        self.texture = texture
        self.function = function
        self.arguments = arguments
        self.textures = textures
        self.draw = draw
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }

    /// Stretched to whatever it is offered instead of drawn at the texture's
    /// own size — `RenderTextureView.resizable()`'s rule. The shader then runs
    /// over the frame's pixels, not the texture's, so its `resolution` is the
    /// frame and `layer(uv)` resamples.
    public func resizable() -> RenderTextureShaderView {
        var copy = self
        copy.isResizable = true
        return copy
    }
}

extension RenderTextureShaderView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        ViewNode(content: RenderTextureShaderContent(
            path: context.path,
            texture: texture,
            function: function,
            draw: draw,
            arguments: ShaderArguments(arguments, colorScheme: context.environment.colorScheme),
            textures: ShaderTextures(textures),
            isResizable: isResizable
        ))
    }
}

/// Reserves the shader slot and reports where it composites. Emits no draw
/// commands: the pixels arrive through the engine, not the canvas.
struct RenderTextureShaderContent: NodeContent {
    let path: [Int]
    let texture: RenderTexture
    let function: ShaderFunction
    let draw: ShaderDraw
    let arguments: ShaderArguments
    let textures: ShaderTextures
    let isResizable: Bool

    /// The texture's size, as `tex.view()` is — the effect does not change
    /// how much room the image asks for.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        isResizable ? .flexible : .fixed
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        isResizable ? proposal.replacingUnspecifiedDimensions(by: texture.size) : texture.size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0, let host = ShaderHost.current else { return }
        host.useTexture(
            path: path,
            function: function,
            draw: draw,
            arguments: arguments,
            textures: textures,
            rect: rect,
            clip: context.compositeClip,
            texture: texture
        )
        host.boundaries.noteNested(at: list.commands.count, rect: context.compositeClip.map { rect.intersection($0) } ?? rect)
    }
}

extension RenderTexture {

    /// This texture with `function` run over its pixels.
    ///
    /// `layer(uv)` reads the texture, as it reads the view under
    /// `.shader(_:)` — so one effect works on either, and nothing written
    /// against it has to know which it was given:
    ///
    /// ```swift
    /// panel.shader(blur, arguments: [.float("radius", 8)])
    /// ```
    ///
    /// Drawn at the texture's own size unless `.resizable()`. `textures` are
    /// further `RenderTexture`s the body samples by name, so a two-layer mix
    /// is `a.shader(mix, textures: [.init("b", b)])`.
    ///
    /// - Parameters:
    ///   - vertices: with a vertex stage, vertices per instance.
    ///   - instances: how many times the vertex stage runs over them.
    public func shader(
        _ function: ShaderFunction,
        arguments: [ShaderArgument] = [],
        textures: [ShaderTextureInput] = [],
        vertices: Int = 6,
        instances: Int = 1,
        _viewID: ViewID = #viewID
    ) -> RenderTextureShaderView {
        RenderTextureShaderView(
            texture: self,
            function: function,
            arguments: arguments,
            textures: textures,
            draw: ShaderDraw(vertices: max(0, vertices), instances: max(0, instances)),
            _viewID: _viewID
        )
    }
}
