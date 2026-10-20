//
//  ShaderProtocol+RenderTexture.swift
//  NucleantUI
//

extension ShaderProtocol {

    /// Run the shader once over `texture`'s pixels and put the result in it.
    ///
    /// No view and no tree: the module is dispatched at the texture's pixel
    /// size into an image of its own, and that is copied into the texture's —
    /// so everything showing the texture (`tex.view()`) or sampling it in
    /// another shader sees the new pixels. Its input is packed now, so the
    /// render is of the values as they are at this call.
    ///
    /// It runs at the top of the next frame, once the window's GPU is up and
    /// the texture has an image. A later `render()` or `update { }` of the
    /// texture's view tree replaces it, as this replaces what that drew.
    /// A compute module only; one with a vertex + fragment pair is logged and
    /// left out.
    ///
    /// ```swift
    /// shader.observe { [weak self] shader in
    ///     guard let self else { return false }
    ///     shader.render(into: self.thumbnail)
    ///     return true
    /// }
    /// ```
    @MainActor
    public func render(into texture: RenderTexture) {
        var bytes: [UInt8] = []
        input.pack(into: &bytes)
        texture.prepareImage()
        texture.pendingShader = (spirv, bytes)
    }

    /// A new texture of `size` points at `scale` pixels per point, with the
    /// shader rendered into it — see `render(into:)`.
    @MainActor
    public func renderTexture(size: Size, scale: Double = 1) -> RenderTexture {
        let texture = RenderTexture(size: size, scale: scale) { Color.clear }
        render(into: texture)
        return texture
    }
}
