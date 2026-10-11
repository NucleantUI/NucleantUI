//
//  RenderTexture.swift
//  NucleantUI
//
//  A view tree rendered into a GPU texture a model can hold — the FBO of this
//  framework.
//
//  Everything else GPU-side here is keyed to a view and retired when the view
//  is not seen in a pass (`ShaderSlotRegistry.endPass`,
//  `RenderNodeManager.retireUnused`). A texture a data model holds has no
//  view, so its owner is the Swift reference: while the object is alive its
//  image is alive, and when the last reference goes the image is recycled at
//  the top of the next frame (`RenderTextureManager.releasePending`) — the
//  same detach-now, free-later rule, for the same MoltenVK use-after-free
//  reason.
//
//  It is a *snapshot*, not a second live view tree. It renders when it is
//  asked to (`render()`, `update { }`) and at no other time: see
//  `OffscreenRender` for why, and `renderImage` for the CPU equivalent that
//  needs no window at all.
//

import CVulkan
import NucleantVulkan

/// A view tree drawn into a texture of its own, for showing anywhere in the
/// tree and for feeding to a shader.
///
/// ```swift
/// @MainActor @Observable
/// final class Layer {
///     let art = renderTexture(size: Size(width: 512, height: 512), scale: 2) {
///         Badge(level: 3)
///     }
/// }
///
/// layer.art.view()                    // show it, anywhere, as often as you like
/// layer.art.update { Badge(level: 4) } // new content, same image
/// ```
///
/// The texture is the size it was made at, in points, at `scale` pixels per
/// point — it is never resized, so a 4000×4000 one is a 64MB image for as
/// long as it is held.
///
/// What a texture is not: a live view. Nothing inside it has input or hit
/// testing, its `onAppear` never runs, and it does not re-render when state
/// it read changes — `@State` inside it keeps its value across renders, but
/// only an explicit `render()` or `update { }` draws again. A `Shader`,
/// `VertexShader`, `TextureView` or `ThorCanvas` nested inside draws nothing
/// (there is no window rect for it to composite into); a `.drawingGroup()` or
/// `.shader(_:)` inside is flattened into the texture's own canvas.
@MainActor
public final class RenderTexture {

    /// Its size in points, and the backing-store pixels per point it was
    /// rasterized at.
    public let size: Size
    public let scale: Double

    public var pixelWidth: Int { max(0, Int((size.width * scale).rounded())) }
    public var pixelHeight: Int { max(0, Int((size.height * scale).rounded())) }

    /// Whether the texture's image holds pixels — false until the first
    /// render that found a GPU to render into.
    public private(set) var hasContent = false

    /// Bumped by every render. A shader sampling this texture re-dispatches
    /// when it changes, which is what makes a static shader over a texture
    /// show the texture's new pixels rather than the ones it was built with.
    private(set) var generation = 0

    /// The tree, kept across renders: a second render reuses the views that
    /// are still equivalent, so the `@State` inside them survives.
    private let tree: OffscreenRender

    /// How to produce the display list again. Replaced by `update { }`.
    private var draw: @MainActor () -> DisplayList

    /// What the last render produced, in the texture's own coordinates.
    /// Kept so the texture can be drawn again when it finally finds a GPU —
    /// a texture made before the window's engine exists is perfectly legal.
    private(set) var content = DisplayList()

    /// The pooled canvas node the content is rasterized into, once a registry
    /// exists. Recycled a frame after this object goes away.
    private var canvas: RenderNodeManager.CanvasNode?

    /// The image a placement borrows and a shader samples.
    var gpuImage: (image: VkImage, view: VkImageView, width: Int, height: Int)? {
        guard let canvas else { return nil }
        return (canvas.node.image, canvas.node.imageView, canvas.width, canvas.height)
    }

    /// The container id the canvas composites under — what `engine.readable`
    /// is keyed by, and so how `image()` knows the GPU has drawn it.
    var canvasID: Int? { canvas?.container.id }

    public init<Content: View>(
        size: Size,
        scale: Double = 1,
        @ViewBuilder content: @escaping () -> Content
    ) {
        var environment = EnvironmentValues()
        environment.displayScale = scale
        let tree = OffscreenRender(environment: environment)
        self.size = size
        self.scale = scale
        self.tree = tree
        self.draw = { tree.list(of: content(), size: size) }
        render()
    }

    /// `RenderTexture(size:scale:content:)` with the view as a value.
    public convenience init<Content: View>(size: Size, scale: Double = 1, content: Content) {
        self.init(size: size, scale: scale, content: { content })
    }

    // MARK: - Rendering

    /// Draw the content again — the same view, re-evaluated, so a model it
    /// reads shows its current values.
    ///
    /// Called during a layout pass, the render is queued and run at the end of
    /// that pass rather than nested inside it: one tree at a time is a hard
    /// rule, not a preference (`OffscreenRender`).
    public func render() {
        guard pixelWidth > 0, pixelHeight > 0 else { return }
        if let pass = ShaderHost.current {
            pass.renderTextures.queue { [weak self] in self?.drawNow() }
            return
        }
        drawNow()
    }

    /// New content, same texture: replaces the view and renders it.
    public func update<Content: View>(@ViewBuilder _ content: @escaping () -> Content) {
        let tree = self.tree
        let size = self.size
        draw = { tree.list(of: content(), size: size) }
        render()
    }

    private func drawNow() {
        content = draw()
        // Counted here, not after the canvas draw: the content is what a
        // shader reading this texture is behind, and a texture rendered
        // before any window existed has new content just the same.
        generation += 1
        attach()
        guard let canvas else { return }
        canvas.render(content, at: [OffscreenRender.rootIndex])
        hasContent = true
        // Placements already put down this pass were told `hasContent` as it
        // was *before* this render; a queued render lands after them.
        ShaderHost.attached?.renderTextures.textureDidRender(self)
    }

    /// Make sure there is an image to bind, without walking the view tree.
    ///
    /// A shader sampling this texture needs a `VkImageView` before its
    /// descriptor set can be written, and `ShaderContent.place` asks for one
    /// from *inside* a layout pass — where a render is queued rather than run
    /// (`render()`), so the image would not exist until the pass was over.
    /// Taking the canvas is not a render, though, and rasterizing the display
    /// list the texture already holds is a backend draw like a `.shader`
    /// layer's: both are safe here, and both leave the image in the layout a
    /// sampler reads from rather than an untouched allocation.
    func prepareImage() {
        guard canvas == nil, pixelWidth > 0, pixelHeight > 0 else { return }
        attach()
        guard let canvas else { return }
        canvas.render(content, at: [OffscreenRender.rootIndex])
        hasContent = !content.commands.isEmpty
        generation += 1
    }

    /// Take a canvas from the registry the first time there is one to take.
    /// A texture built before the window's engine exists keeps its display
    /// list and gets its image here instead.
    private func attach() {
        guard canvas == nil, let registry = ShaderHost.attached else { return }
        canvas = registry.renderTextures.makeBacking(
            for: self,
            width: pixelWidth,
            height: pixelHeight,
            scale: scale
        )
    }

    // MARK: - Out

    /// The texture's pixels, read back from the GPU.
    ///
    /// Blocking: it drains a copy through the device and waits for it. This is
    /// for export and for tests, never a frame path. `nil` when the texture
    /// has no image yet, or when the engine has not drawn its canvas since
    /// the last render — the pixels only exist once a frame has run. The
    /// headless equivalent, which needs no engine at all, is
    /// `renderImage(size:scale:content:)`.
    public func image() -> RasterImage? {
        guard hasContent, let registry = ShaderHost.attached else { return nil }
        return registry.renderTextures.readback(of: self)
    }

    /// The texture as a view: its image composited into the frame.
    ///
    /// Drawn at its own size in points, like `Image` — `.resizable()` takes
    /// whatever it is offered instead. The same texture may be placed as many
    /// times as you like; each placement borrows the one image.
    public func view(_viewID: ViewID = #viewID) -> RenderTextureView {
        RenderTextureView(texture: self, _viewID: _viewID)
    }
}

extension RenderTexture: ViewInput {
    /// By identity: the object is the texture, and its pixels changing is not
    /// a reason to rebuild the views showing it — a placement re-places every
    /// pass and samples the image as it then stands.
    public func _isEquivalent(to other: RenderTexture) -> Bool { self === other }
}

/// `content` laid out at `size` points and drawn into a texture of its own at
/// `scale` pixels per point — see `RenderTexture`.
///
/// ```swift
/// let tex = renderTexture(size: Size(width: 256, height: 256), scale: 2) {
///     Dial(value: 0.7)
/// }
/// ```
@MainActor
public func renderTexture<Content: View>(
    size: Size,
    scale: Double = 1,
    @ViewBuilder content: @escaping () -> Content
) -> RenderTexture {
    RenderTexture(size: size, scale: scale, content: content)
}

extension View {

    /// This view, drawn into a texture of its own — the trailing form of
    /// `renderTexture(size:scale:content:)`.
    ///
    /// Not a `ViewModifier`: it returns a texture, not a view. `panel.texture(size:)`
    /// reads like one and is not — nothing in a view tree changes by calling
    /// it, and the result is an object to hold, like SwiftUI's
    /// `ImageRenderer`. The view is evaluated once per render, so hold the
    /// texture and call `render()` rather than calling this again.
    @MainActor
    public func texture(size: Size, scale: Double = 1) -> RenderTexture {
        RenderTexture(size: size, scale: scale, content: self)
    }
}
