//
//  ShaderSlotRegistry.swift
//  NucleantUI
//
//  A `Shader` view does not draw into the shared window canvas — it cannot,
//  the canvas is a 2D vector surface. It gets its own GPU node, composited
//  into its own rect of the swapchain, which is what `RenderContainerNode`'s
//  `compositeRect` is for.
//
//  That means slots have a *lifetime tied to the view tree*: created when a
//  Shader view first appears, moved and resized as it is laid out, destroyed
//  when it goes away. This registry is that bookkeeping, and the one place in
//  the framework where the view layer reaches the engine directly.
//
//  A `.shader(_:)` effect is the same slot with one more piece: a canvas
//  of its own that the view is drawn into, bound to the compute
//  shader as a texture. Two engine nodes, then — the canvas, which is never
//  composited, and the effect's output, which is — updated in that order.
//
//  A `VertexShader` view is the same slot again with a graphics pipeline in
//  place of the compute one: its image is a colour attachment drawn by a
//  render pass, and composited exactly like the others.
//
//  The canvases themselves — a `.shader` layer's, the per-view nodes of
//  `.drawingGroup()`, and `ThorCanvas`'s — are `RenderNodeManager`'s, which
//  this registry owns and drives through the same pass lifecycle; layers and
//  drawing groups share one pool of the build's canvases (`CanvasBackend`). Slots and nodes are composited in the order
//  the tree placed them (`nextPaintOrder`), not the order they were built.
//

import CVulkan
import VulkanCore
import NucleantVulkan
import NucleantThorVG
import Dispatch
import Observation

@MainActor
final class ShaderSlotRegistry<N: NucleantContainerNode> {

    /// What a slot draws with: a compute dispatch or a vertex + fragment pass.
    @MainActor
    enum Backend {
        case compute(ComputeShaderNode<N>, ShaderPipeline)
        case graphics(VertFragShaderNode<N>, VertexShaderPipeline)

        var argumentCapacity: Int {
            switch self {
            case .compute(_, let pipeline): return pipeline.argumentCapacity
            case .graphics(_, let pipeline): return pipeline.argumentCapacity
            }
        }

        func update(_ uniforms: ShaderUniforms) {
            switch self {
            case .compute(_, let pipeline): pipeline.update(uniforms)
            case .graphics(_, let pipeline): pipeline.update(uniforms)
            }
        }

        func updateArguments(_ packed: [Float]) {
            switch self {
            case .compute(_, let pipeline): pipeline.updateArguments(packed)
            case .graphics(_, let pipeline): pipeline.updateArguments(packed)
            }
        }

        func updateArguments(bytes: [UInt8]) {
            switch self {
            case .compute(_, let pipeline): pipeline.updateArguments(bytes: bytes)
            case .graphics(_, let pipeline): pipeline.updateArguments(bytes: bytes)
            }
        }
    }

    /// What a view asks its slot to be.
    enum Request {
        case compute(ShaderFunction, withLayer: Bool)
        case graphics(VertexShaderFunction, ShaderDraw, withLayer: Bool)
        /// A `ShaderProtocol`'s module, compiled already: dispatched or
        /// drawn by what its entry points say.
        case module([UInt32], SpirvEntryPoints, ShaderDraw, isAnimated: Bool)

        /// Identity for the compiled pipeline; the kind is part of it, so a
        /// path that changes view type rebuilds.
        var source: String {
            switch self {
            case .compute(let function, _): return function.source
            case .graphics(let function, _, _): return "#graphics\n" + function.source
            // The words themselves are compared — see `words`.
            case .module: return "#module"
            }
        }

        /// A module's words, compared as they are: the same array is the
        /// same storage, so an unchanged module costs nothing to compare.
        /// Empty for a source function, whose identity is `source`.
        var words: [UInt32] {
            switch self {
            case .module(let words, _, _, _): return words
            case .compute, .graphics: return []
            }
        }

        var isAnimated: Bool {
            switch self {
            case .compute(let function, _): return function.isAnimated
            case .graphics(let function, _, _): return function.isAnimated
            case .module(_, _, _, let isAnimated): return isAnimated
            }
        }

        var withLayer: Bool {
            switch self {
            case .compute(_, let withLayer), .graphics(_, _, let withLayer): return withLayer
            case .module: return false
            }
        }
    }

    /// One live shader view's GPU state.
    @MainActor
    final class Slot {
        let backend: Backend
        let container: N
        /// For a `.shader(_:)` effect: the canvas the view is drawn into,
        /// which the shader samples. `nil` for a generative `Shader` view —
        /// and for a retired effect slot whose canvas has been handed on.
        var layer: Layer?
        /// For a `.shader(_:)` over a `ThorCanvas` / `ThorCanvasRender`: that
        /// view's own canvas node, whose image the shader samples in place of
        /// a layer. Borrowed — `RenderNodeManager` keeps and frees it — and
        /// `canvasView` is the image view the pipeline was bound to, so a
        /// node that got a new image gets a new slot.
        let canvas: RenderNodeManager<N>.ThorCanvasNode?
        let canvasView: VkImageView?
        /// For `tex.shader(_:)`: the `RenderTexture` whose image is what the
        /// shader samples as its content, in place of a layer. Borrowed the
        /// same way — the texture owns the image and frees it — so a texture
        /// that got a new one gets a new slot.
        let contentTexture: RenderTexture?
        let contentTextureView: VkImageView?
        /// That texture's `generation` when the shader last ran, so a texture
        /// that rendered again re-dispatches a static shader over it.
        var contentGeneration: Int
        /// Pixel size the node was built at — a resize rebuilds it.
        var width: Int
        var height: Int
        /// Source it was compiled from; a change recompiles.
        var source: String
        /// The module it was built from, for a `ShaderProtocol` — compared
        /// alongside `source`.
        var words: [UInt32]
        /// A `ShaderProtocol`'s input: which object, how to pack it, and the
        /// bytes last uploaded. A change to anything `pack` reads is noticed
        /// by observation and uploaded at the next `tick`, with no pass.
        var inputID: ObjectIdentifier?
        var pack: (() -> [UInt8])?
        var packedBytes: [UInt8] = []
        /// The argument names and kinds compiled in, and the values last
        /// uploaded — a change to the former rebuilds, to the latter
        /// re-uploads and re-dispatches.
        var argumentSignature: String
        var packedArguments: [Float] = []
        /// The named textures compiled in, and every image the descriptor set
        /// was written with (content first, then the textures in binding
        /// order).
        ///
        /// The names are part of the compiled shader, so a change there
        /// rebuilds the slot. A texture that merely has a *different image* is
        /// a descriptor rebind instead (`ShaderPipeline.rebindDescriptors`) —
        /// which needs the whole list, since a set can only be rewritten with
        /// the bindings it was built for.
        var textureSignature: String
        var boundInputs: [ShaderImageInput]
        /// The textures themselves, so a render that lands *after* the slot
        /// was placed can still be noticed — see `endPass`.
        var textures: ShaderTextures
        /// Each texture's `generation` when the shader last ran.
        var textureGenerations: [Int]

        /// The image views bound at binding 4 and up — the named textures,
        /// without the content.
        var textureViews: [VkImageView] {
            boundInputs.filter { $0.binding >= 4 }.map(\.imageView)
        }
        /// Whether the source reads the clock or the pointer. If not, one
        /// dispatch is all it needs until its input changes.
        let isAnimated: Bool
        /// Seen during the current layout pass. Anything not seen has left
        /// the tree and is torn down.
        var used = true
        /// Seconds since this shader appeared, fed to the `time` uniform.
        var elapsed: Double = 0
        /// Frames drawn since it appeared — ShaderToy's `iFrame`.
        var frame: Int = 0
        /// Where the view was last placed, in points — the pointer uniform
        /// is relative to it.
        var rect: Rect = .zero
        /// `rect`'s origin snapped to a whole pixel, in points: where the
        /// image is actually composited, and so where a layer's content is
        /// drawn from, so that texels land on pixels rather than between
        /// them (a fractional origin bilinearly blurs the whole layer).
        var pixelOrigin: Point = .zero

        init(
            backend: Backend,
            container: N,
            layer: Layer?,
            canvas: RenderNodeManager<N>.ThorCanvasNode?,
            contentTexture: RenderTexture?,
            inputs: [ShaderImageInput],
            width: Int,
            height: Int,
            request: Request,
            arguments: ShaderArguments,
            textures: ShaderTextures
        ) {
            self.backend = backend
            self.container = container
            self.layer = layer
            self.canvas = canvas
            self.canvasView = canvas?.node.imageView
            self.contentTexture = contentTexture
            self.contentTextureView = contentTexture?.gpuImage?.view
            self.contentGeneration = contentTexture?.generation ?? 0
            self.width = width
            self.height = height
            self.source = request.source
            self.words = request.words
            self.argumentSignature = arguments.signature
            self.textureSignature = textures.signature
            self.boundInputs = inputs
            self.textures = textures
            self.textureGenerations = textures.generations
            self.isAnimated = request.isAnimated
        }
    }

    /// The view side of a `.shader(_:)` slot: a canvas the size of the
    /// view, rasterized whenever the view draws something different, and
    /// sampled by the slot's compute shader as `uContent`. A per-view canvas
    /// node that is never composited — `content` and `origin` are what it
    /// holds and where the view was when it was drawn; an identical list at
    /// the same place is not drawn again.
    typealias Layer = RenderNodeManager<N>.CanvasNode

    private unowned let engine: VulkanRenderEngine<N>

    /// The per-view render nodes (and the canvas pool the layers share),
    /// the painter that fills the automatic image nodes, and the
    /// boundaries a pass's drawing splits at.
    let renderNodes: RenderNodeManager<N>
    let painter: NodePainter<N>
    let boundaries: RenderBoundaries<N>
    /// The `TextureView` nodes, whose pixels their sources write.
    let textures: TextureNodeManager<N>
    /// The `RenderTexture` canvases, and the containers that show one in the
    /// tree. Unlike everything else here, a texture's lifetime is its owner's
    /// Swift reference rather than the pass.
    let renderTextures: RenderTextureManager<N>

    /// Keyed by the view's structural path — the same identity `@State` uses,
    /// so a shader keeps its pipeline across rebuilds and loses it only when
    /// the view itself goes away.
    private var slots: [[Int]: Slot] = [:]

    /// Backing-store pixels per point.
    var scale: Double = 1 {
        didSet {
            renderNodes.scale = scale
            painter.scale = scale
        }
    }

    /// Slots detached from the engine but not yet freed — see `endPass`.
    private var pendingDestroy: [Slot] = []

    /// Paths whose `ShaderProtocol` input changed since it was last packed,
    /// set by observation and served by `tick`.
    private var changedInputs: Set<[Int]> = []

    /// What renders a shader into a `RenderTexture`, per texture — see
    /// `renderPendingShaders`.
    private var textureShaders: [ObjectIdentifier: TextureShader] = [:]

    init(engine: VulkanRenderEngine<N>) {
        self.engine = engine
        self.renderNodes = RenderNodeManager(engine: engine)
        self.painter = NodePainter(engine: engine, nodes: renderNodes)
        self.boundaries = RenderBoundaries(nodes: renderNodes, painter: painter)
        self.textures = TextureNodeManager(engine: engine, renderNodes: renderNodes)
        self.renderTextures = RenderTextureManager(engine: engine, renderNodes: renderNodes)
        // What a `RenderTexture` made outside any pass reaches for.
        ShaderHost.attached = self as? ShaderSlotRegistry<NucleantRenderNode>
    }

    // MARK: - Layout-pass lifecycle

    /// `windowSize` is the window's content size in points — what bounds a
    /// per-view node's image.
    func beginPass(windowSize: Size) {
        for slot in slots.values { slot.used = false }
        renderNodes.beginPass(windowSize: windowSize)
        boundaries.beginPass()
        textures.beginPass()
        renderTextures.beginPass()
    }

    /// Called from `ShaderContent.place`: make sure a slot exists for this
    /// view, at this size, and put it at this rect.
    func use(
        path: [Int],
        function: ShaderFunction,
        arguments: ShaderArguments,
        textures: ShaderTextures = .none,
        rect: Rect,
        clip: Rect?
    ) {
        _ = slot(
            at: path,
            request: .compute(function, withLayer: false),
            arguments: arguments,
            textures: textures,
            rect: rect,
            clip: clip
        )
    }

    /// Called from `ShaderModuleContent.place`: the slot for a
    /// `ShaderProtocol`'s module, with `input` packed into its argument
    /// buffer.
    ///
    /// The input is packed under observation here only when it is new or
    /// changed; otherwise a change to it is noticed by observation and
    /// uploaded by `tick`, without the view tree.
    func useModule<Input: ShaderInput>(
        path: [Int],
        words: [UInt32],
        input: Input,
        isAnimated: Bool,
        draw: ShaderDraw,
        textures: ShaderTextures,
        rect: Rect,
        clip: Rect?
    ) {
        let stages = SpirvEntryPoints(words)
        let existing = slots[path]
        let inputID = ObjectIdentifier(input)
        let pack = {
            var bytes: [UInt8] = []
            input.pack(into: &bytes)
            return bytes
        }
        var bytes = existing?.packedBytes ?? []
        let repack = existing == nil || existing?.inputID != inputID
            || existing?.words != words || changedInputs.contains(path)
        if repack {
            changedInputs.remove(path)
            bytes = track(pack, at: path)
        }
        guard let slot = slot(
            at: path,
            request: .module(words, stages, draw, isAnimated: isAnimated),
            arguments: .none,
            inputBytes: bytes.count,
            textures: textures,
            rect: rect,
            clip: clip
        ) else { return }
        slot.inputID = inputID
        slot.pack = pack
        upload(bytes, to: slot)
        if stages.isGraphics {
            redraw(slot, covering: draw)
        }
    }

    /// Run `pack` under observation: the first change to anything it read
    /// files `path` for the next `tick`. The handler runs on whichever
    /// thread wrote, so it hops to the main queue the frames are served on.
    private func track(_ pack: () -> [UInt8], at path: [Int]) -> [UInt8] {
        withObservationTracking(pack) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { _ = self?.changedInputs.insert(path) }
            }
        }
    }

    /// Hand the slot its input's bytes if they changed, and make it draw
    /// again.
    private func upload(_ bytes: [UInt8], to slot: Slot) {
        guard bytes != slot.packedBytes else { return }
        slot.backend.updateArguments(bytes: bytes)
        slot.packedBytes = bytes
        slot.container.needsRender = true
    }

    /// Called from `VertexShaderContent.place`: the graphics slot for this
    /// view, drawing `draw` this frame.
    func useGraphics(
        path: [Int],
        function: VertexShaderFunction,
        draw: ShaderDraw,
        arguments: ShaderArguments,
        textures: ShaderTextures = .none,
        rect: Rect,
        clip: Rect?
    ) {
        guard let slot = slot(at: path, request: .graphics(function, draw, withLayer: false),
                              arguments: arguments, textures: textures, rect: rect, clip: clip)
        else { return }
        redraw(slot, covering: draw)
    }

    /// The per-frame half of a graphics slot: how much the next draw covers.
    /// No rebuild, just a redraw when it changes.
    private func redraw(_ slot: Slot, covering draw: ShaderDraw) {
        guard case .graphics(let node, _) = slot.backend else { return }
        let vertices = UInt32(draw.vertices), instances = UInt32(draw.instances)
        guard node.vertexCount != vertices || node.instanceCount != instances else { return }
        node.vertexCount = vertices
        node.instanceCount = instances
        slot.container.needsRender = true
    }

    /// Called from `ShaderEffectContent.place`: the slot for this view with
    /// `content` — what the view drew this pass — in its canvas. `function`
    /// says which pipeline reads it: a compute dispatch over every pixel, or
    /// a vertex + fragment pair drawing `draw` over it.
    func useLayer(
        path: [Int],
        function: ShaderFunction,
        draw: ShaderDraw,
        arguments: ShaderArguments,
        textures: ShaderTextures = .none,
        rect: Rect,
        clip: Rect?,
        content: DisplayList
    ) {
        let request: Request = function.isGraphics
            ? .graphics(function, draw, withLayer: true)
            : .compute(function, withLayer: true)
        guard let slot = slot(at: path, request: request, arguments: arguments,
                              textures: textures, rect: rect, clip: clip),
              let layer = slot.layer
        else { return }
        if function.isGraphics {
            redraw(slot, covering: draw)
        }
        // Absolute coordinates, so a view that merely moved reads as changed
        // and is drawn again at its new place; the canvas transform absorbs
        // the origin, but the comparison does not.
        guard layer.content != content || layer.origin != slot.pixelOrigin else { return }
        if PerfTrace.isEnabled { PerfTrace.layersDrawn += 1 }
        layer.renderer.render(content, origin: slot.pixelOrigin, flipHeight: slot.height)
        layer.content = content
        layer.origin = slot.pixelOrigin
        // Rasterize the canvas, then resample it — whether or not the shader
        // itself is animated.
        layer.container.needsRender = true
        slot.container.needsRender = true
    }

    /// Called from `ShaderEffectContent.place` when the view is a single
    /// canvas node: the slot for this view, sampling `canvas`'s own image.
    /// `changed` — the canvas was rasterized again this pass — re-runs the
    /// shader over it, as new content in a layer does.
    func useCanvas(
        path: [Int],
        function: ShaderFunction,
        draw: ShaderDraw,
        arguments: ShaderArguments,
        textures: ShaderTextures = .none,
        rect: Rect,
        clip: Rect?,
        canvas: RenderNodeManager<N>.ThorCanvasNode,
        changed: Bool
    ) {
        let request: Request = function.isGraphics
            ? .graphics(function, draw, withLayer: true)
            : .compute(function, withLayer: true)
        guard let slot = slot(at: path, request: request, arguments: arguments,
                              textures: textures, rect: rect, clip: clip, canvas: canvas)
        else { return }
        if function.isGraphics {
            redraw(slot, covering: draw)
        }
        if changed {
            slot.container.needsRender = true
        }
    }

    /// Called from `RenderTextureShaderContent.place`: the slot for
    /// `tex.shader(_:)` — the texture's own image is what the shader samples
    /// as its content, in place of a layer or a canvas node. A texture that
    /// rendered again re-runs the shader over it, as new content in a layer
    /// does.
    func useTexture(
        path: [Int],
        function: ShaderFunction,
        draw: ShaderDraw,
        arguments: ShaderArguments,
        textures: ShaderTextures = .none,
        rect: Rect,
        clip: Rect?,
        texture: RenderTexture
    ) {
        let request: Request = function.isGraphics
            ? .graphics(function, draw, withLayer: true)
            : .compute(function, withLayer: true)
        guard let slot = slot(at: path, request: request, arguments: arguments,
                              textures: textures, rect: rect, clip: clip, texture: texture)
        else { return }
        if function.isGraphics {
            redraw(slot, covering: draw)
        }
        if slot.contentGeneration != texture.generation {
            slot.contentGeneration = texture.generation
            slot.container.needsRender = true
        }
    }

    /// The slot standing at `path`, rebuilt if its size or source changed,
    /// created if there is none; placed at `rect` either way. `canvas` is the
    /// canvas node it samples instead of a layer of its own.
    private func slot(
        at path: [Int],
        request: Request,
        arguments: ShaderArguments,
        inputBytes: Int = 0,
        textures: ShaderTextures,
        rect: Rect,
        clip: Rect?,
        canvas canvasInput: RenderNodeManager<N>.ThorCanvasNode? = nil,
        texture textureInput: RenderTexture? = nil
    ) -> Slot? {
        let source = request.source
        // What the argument buffer has to hold, in floats: the arguments'
        // packed list, or a `ShaderProtocol` input's bytes.
        let argumentFloats = max(arguments.packed.count, (inputBytes + 3) / 4)
        // A slot sampling a canvas node or a texture has no layer of its own.
        let withLayer = request.withLayer && canvasInput == nil && textureInput == nil
        let pixelWidth = max(1, Int((rect.width * scale).rounded()))
        let pixelHeight = max(1, Int((rect.height * scale).rounded()))

        // Every image a descriptor is written with has to exist first. A
        // texture that has never rendered takes its canvas here, inside the
        // pass, rather than at the end of it — see `RenderTexture.prepareImage`.
        textures.prepare()
        textureInput?.prepareImage()
        guard let textureInputs = textures.imageInputs else {
            nucleantLogError(
                "NucleantUI: shader at \(path) samples \(textures.signature) — "
                + "no image for one of them, so nothing is drawn this frame\n"
            )
            return nil
        }

        // This slot's place in the composite order is where the tree placed
        // it, whether the GPU objects are kept or rebuilt below.
        let order = renderNodes.nextPaintOrder()
        var previous: Slot?
        var canvas: Layer?
        if let existing = slots[path] {
            existing.used = true
            // Both rects are read fresh by the engine every frame, so moving or
            // re-clipping a shader view is free; only a *resize*, a source
            // change, or an argument list the buffer can't hold needs the GPU
            // objects rebuilt.
            place(existing, rect: rect, clip: clip)
            if existing.width == pixelWidth,
               existing.height == pixelHeight,
               existing.source == source,
               existing.words == request.words,
               existing.argumentSignature == arguments.signature,
               existing.backend.argumentCapacity >= argumentFloats,
               existing.textureSignature == textures.signature,
               (existing.layer != nil) == withLayer,
               existing.canvas === canvasInput,
               existing.canvasView == canvasInput?.node.imageView,
               existing.contentTexture === textureInput,
               existing.contentTextureView == textureInput?.gpuImage?.view {
                // Same shader, same textures by name — but a `RenderTexture`
                // that was re-attached has a new image, and the descriptor
                // set snapshots the handle it was written with.
                if existing.textureViews != textureInputs.map(\.imageView) {
                    rebind(existing, to: existing.boundInputs.filter { $0.binding < 4 } + textureInputs)
                }
                // A texture that rendered again is new input to a shader that
                // may never dispatch on its own.
                existing.textures = textures
                if existing.textureGenerations != textures.generations {
                    existing.textureGenerations = textures.generations
                    existing.container.needsRender = true
                }
                upload(arguments, to: existing)
                composite(existing, at: order)
                return existing
            }
            // Retire it the way `endPass` does — detach now, free at the top
            // of the next frame. Freeing here, mid-frame, is the same
            // use-after-free §8 fixed for teardown: command buffers still in
            // flight reference the image, and the old container would stay
            // in `engine.nodes` for the composite pass to draw from freed
            // memory. Seen as a segfault inside MoltenVK on maximizing a
            // window with a shader on screen.
            //
            // Its canvas, though, is handed straight to the replacement: the
            // retargeting is in place, and the spare pool is only refilled
            // once the old GPU objects are freed, a frame from now.
            retire(existing)
            if withLayer {
                canvas = existing.layer
                existing.layer = nil
            }
            slots[path] = nil
            previous = existing
        }

        guard let slot = makeSlot(
            request: request,
            arguments: arguments,
            argumentFloats: argumentFloats,
            textures: textures,
            textureInputs: textureInputs,
            width: pixelWidth,
            height: pixelHeight,
            layer: canvasInput.map { .canvas($0) }
                ?? textureInput.map { .texture($0) }
                ?? (withLayer ? .reuse(canvas) : .none)
        ) else {
            return nil
        }
        // Same view, new image: the animation continues rather than restarts.
        if let previous {
            slot.elapsed = previous.elapsed
            slot.frame = previous.frame
        }
        place(slot, rect: rect, clip: clip)
        upload(arguments, to: slot)
        composite(slot, at: order)
        slots[path] = slot
        return slot
    }

    /// File the slot — and its layer canvas just before it, so the engine
    /// draws the canvas before the shader samples it — at `order`.
    private func composite(_ slot: Slot, at order: Int) {
        if let layer = slot.layer {
            renderNodes.composite(layer.container, at: order, layer: true)
        }
        if let canvas = slot.canvas {
            renderNodes.composite(canvas.container, at: order, layer: true)
        }
        renderNodes.composite(slot.container, at: order)
    }

    /// Point a live slot's sampled-image descriptors at new handles.
    ///
    /// Same names, same bindings, different images — a `RenderTexture` that
    /// took its canvas after the slot was built, or was re-attached. The set
    /// may still be bound in a command buffer in flight, so the device is
    /// drained first; a set whose *shape* changed is a rebuild instead, which
    /// is what the texture signature in `slot(at:)` decides.
    private func rebind(_ slot: Slot, to inputs: [ShaderImageInput]) {
        vkDeviceWaitIdle(engine.device)
        switch slot.backend {
        case .compute(let node, let pipeline):
            pipeline.rebindDescriptors(inputs)
            node.inputs = inputs
            node.descriptorsNeedRebind = false
        case .graphics(_, let pipeline):
            pipeline.rebindDescriptors(inputs)
        }
        slot.boundInputs = inputs
        slot.container.needsRender = true
    }

    /// Hand the slot its argument values if they changed, and make it draw
    /// again — a static shader's one dispatch was of the old values.
    private func upload(_ arguments: ShaderArguments, to slot: Slot) {
        guard !arguments.isEmpty, arguments.packed != slot.packedArguments else { return }
        slot.backend.updateArguments(arguments.packed)
        slot.packedArguments = arguments.packed
        slot.container.needsRender = true
    }

    /// Point a slot at its frame, and at whatever its container allows it to
    /// draw within.
    private func place(_ slot: Slot, rect: Rect, clip: Rect?) {
        slot.rect = rect
        // Whole pixels, at the image's own size: a viewport that starts or
        // ends between pixels resamples the image, and a 1:1 mapping is what
        // keeps a layer's text as sharp as it was in the canvas.
        let x = (rect.minX * scale).rounded(.down)
        let y = (rect.minY * scale).rounded(.down)
        slot.pixelOrigin = Point(x: x / scale, y: y / scale)
        slot.container.compositeRect = SIMD4(
            x, y,
            Double(slot.width), Double(slot.height)
        )
        // Intersected here rather than in the engine: `clip` is the container's
        // rect, and what the slot may draw is the part of *its own* frame that
        // falls inside it.
        slot.container.compositeScissor = clip.map { clip in
            let visible = rect.intersection(clip)
            return SIMD4(
                visible.minX * scale, visible.minY * scale,
                visible.width * scale, visible.height * scale
            )
        }
        if LayoutTrace.isEnabled {
            let s = slot.container.compositeScissor
            nucleantLogError(String(
                format: "[layout] shader  rect x=%7.2f y=%7.2f w=%7.2f h=%7.2f  scissor %@\n",
                rect.minX, rect.minY, rect.width, rect.height,
                s.map { String(format: "x=%.2f y=%.2f w=%.2f h=%.2f", $0.x, $0.y, $0.z, $0.w) }
                    ?? "none"
            ))
        }
    }

    /// Retire slots whose views have left the tree.
    ///
    /// Detach now, free later. This runs inside the layout pass, from
    /// `ViewHost.layoutAndRender` — the middle of a frame, with command buffers
    /// for frames still in flight holding references to the image. Freeing here
    /// segfaulted inside MoltenVK even behind a `vkDeviceWaitIdle`. Taking the
    /// slot out of `engine.nodes` stops it compositing immediately (which is
    /// all that has to happen *now*), and the GPU objects are released at the
    /// top of the next frame, outside any recording.
    func endPass() {
        let started = PerfTrace.isVerbose ? DispatchTime.now().uptimeNanoseconds : 0
        var retired = 0
        for (path, slot) in slots where !slot.used {
            retire(slot)
            slots[path] = nil
            changedInputs.remove(path)
            retired += 1
        }
        if retired > 0 {
            PerfTrace.trace("shader slots: retired \(retired) in \(PerfTrace.millis(since: started))")
        }
        // Retire the per-view nodes no view pulled, paint the images with
        // new content, then put the engine's list in this pass's paint
        // order — slots included.
        textures.endPass()
        // Renders a pass asked for run here, before the placements showing
        // them are retired — a texture rendered mid-walk draws now.
        renderTextures.endPass()
        // And a shader reading one of those textures has to be told, now that
        // they have drawn. `use` compared generations as they stood when the
        // view was placed, which is *before* a queued render ran: without
        // this a static composite shows the pixels its textures held when it
        // was built and never looks again. The texture's canvas is unplaced,
        // so the engine draws it before any shader samples it this frame.
        for slot in slots.values where slot.used {
            if slot.textureGenerations != slot.textures.generations {
                slot.textureGenerations = slot.textures.generations
                slot.container.needsRender = true
            }
            if let texture = slot.contentTexture, slot.contentGeneration != texture.generation {
                slot.contentGeneration = texture.generation
                slot.container.needsRender = true
            }
        }
        renderNodes.retireUnused()
        boundaries.endPass()
        painter.paintPending()
        renderNodes.endPass()
    }

    /// Take a slot out of the engine now and queue its GPU objects for
    /// `releasePending`. Drops the engine's per-slot descriptor set, pool
    /// and readable marker — `remove(id:)` would do this too, but it also
    /// frees the node, which is exactly what is being deferred.
    private func retire(_ slot: Slot) {
        let ids = [slot.container.id, slot.layer?.container.id].compactMap { $0 }
        engine.nodes.removeAll { ids.contains($0.id) }
        for id in ids { engine.invalidateComposite(id: id) }
        pendingDestroy.append(slot)
    }

    // MARK: - Per frame

    /// Advance every live shader's clock and hand it to the GPU, then flag the
    /// animated slots for redraw.
    ///
    /// A shader that reads the clock or the pointer wants a dispatch every
    /// frame — unlike the window canvas, that is the one thing on screen which
    /// is never idle. One that reads neither is left alone: its first dispatch
    /// (the slot starts `needsRender`) produced everything it will ever
    /// produce, until a `.shader` layer's content changes and `useLayer`
    /// re-arms it. Returns true when at least one slot is live, so the window
    /// knows the frame was not free.
    @discardableResult
    func tick(_ delta: Double, pointer: Point) -> Bool {
        releasePending()
        // Before the node manager's: a canvas handed back by a texture that
        // was released reaches the pool in this same frame.
        renderTextures.releasePending()
        renderNodes.releasePending()
        textures.releasePending()
        painter.frameWillDraw()
        renderPendingShaders()
        guard !slots.isEmpty else { return false }
        uploadChangedInputs()
        for slot in slots.values {
            slot.elapsed += delta
            slot.frame += 1
            if slot.isAnimated {
                slot.container.needsRender = true
            }
            // The uniforms matter only to a dispatch: an animated slot's,
            // or a static one's first or re-armed one.
            guard slot.container.needsRender else { continue }
            // One pointer for every shader, in window pixels: two shaders
            // side by side read the same value and stay in step with each
            // other, which per-view coordinates never did.
            let local = Point(
                x: pointer.x * scale,
                y: pointer.y * scale
            )
            slot.backend.update(ShaderUniforms(
                time: Float(slot.elapsed),
                timeDelta: Float(delta),
                frame: Float(slot.frame),
                resolutionX: Float(slot.width),
                resolutionY: Float(slot.height),
                mouseX: Float(local.x),
                mouseY: Float(local.y),
                // zw is ShaderToy's "position while pressed"; there is no
                // press tracking on this path yet, so it mirrors xy.
                mouseClickX: Float(local.x),
                mouseClickY: Float(local.y)
            ))
        }
        return true
    }

    /// Pack again every `ShaderProtocol` input observation said changed, and
    /// upload it — the whole of what a changed input costs, with no pass
    /// and no view rebuilt. One that outgrew its buffer waits for a pass
    /// over its path instead, which rebuilds the slot with room for it.
    private func uploadChangedInputs() {
        guard !changedInputs.isEmpty else { return }
        for path in changedInputs {
            guard let slot = slots[path], let pack = slot.pack else {
                changedInputs.remove(path)
                continue
            }
            let bytes = track(pack, at: path)
            guard (bytes.count + 3) / 4 <= slot.backend.argumentCapacity else {
                Invalidator.shared.invalidate(owner: path)
                continue
            }
            changedInputs.remove(path)
            upload(bytes, to: slot)
        }
    }

    func destroyAll() {
        for slot in slots.values {
            retire(slot)
        }
        slots.removeAll()
        changedInputs.removeAll()
        if !textureShaders.isEmpty {
            vkDeviceWaitIdle(engine.device)
            for shader in textureShaders.values { shader.destroy(engine) }
            textureShaders.removeAll()
        }
        releasePending()
        painter.destroy()
        textures.destroyAll()
        renderTextures.destroyAll()
        renderNodes.destroyAll()
        if ShaderHost.attached === self { ShaderHost.attached = nil }
    }

    /// Free everything retired by a previous pass. Called at the top of a
    /// frame, before anything is recorded.
    private func releasePending() {
        guard !pendingDestroy.isEmpty else { return }
        let retired = pendingDestroy
        pendingDestroy.removeAll(keepingCapacity: true)
        // One drain for the whole batch: nothing in flight may still reference
        // any of these images.
        vkDeviceWaitIdle(engine.device)
        for slot in retired { destroy(slot) }
    }

    // MARK: - Shaders rendered into textures

    /// The GPU side of `render(into:)` for one texture: a compute node and
    /// pipeline of its own at the texture's pixel size, never composited,
    /// whose output is copied into the texture's image. Kept while the
    /// texture lives, so a texture rendered again — an input that changed —
    /// dispatches the same pipeline again rather than building one.
    @MainActor
    final class TextureShader {
        weak var texture: RenderTexture?
        let words: [UInt32]
        let node: ComputeShaderNode<N>
        let pipeline: ShaderPipeline
        /// Carries the node through its `update`; never in the engine's list.
        let container: N
        /// The clock the module reads: seconds since its first render here.
        let started = DispatchTime.now().uptimeNanoseconds
        var frame = 0

        init(texture: RenderTexture, words: [UInt32], node: ComputeShaderNode<N>, pipeline: ShaderPipeline, container: N) {
            self.texture = texture
            self.words = words
            self.node = node
            self.pipeline = pipeline
            self.container = container
        }

        /// The caller drains the device first.
        func destroy(_ engine: VulkanRenderEngine<N>) {
            node.computePipeline = nil
            node.computeLayout = nil
            node.computeDescriptorSet = nil
            pipeline.destroy()
            node.destroyResources(engine)
        }
    }

    /// Run every shader a texture is waiting for: dispatch it into its own
    /// image and copy that into the texture's, in one submit.
    ///
    /// At the top of a frame, before anything is recorded, and only for a
    /// texture whose canvas the engine has drawn — the copy starts from the
    /// layout that draw left the image in. The submit is waited on, so the
    /// frame that follows samples the new pixels; it costs one dispatch and
    /// one copy, and only when something asked for it.
    private func renderPendingShaders() {
        if textureShaders.values.contains(where: { $0.texture == nil }) {
            // Nothing in flight uses these: every submit of theirs was waited on.
            for (key, shader) in textureShaders where shader.texture == nil {
                shader.destroy(engine)
                textureShaders[key] = nil
            }
        }
        var rendered = false
        for texture in renderTextures.waitingForShader {
            guard let request = texture.pendingShader,
                  let image = texture.gpuImage,
                  let canvasID = texture.canvasID,
                  engine.readable.contains(canvasID)
            else { continue }
            texture.pendingShader = nil
            guard let entryPoint = SpirvEntryPoints(request.words).compute else {
                nucleantLogError("NucleantUI: render(into:) runs a compute module; this one has no compute entry point\n")
                continue
            }
            guard let shader = textureShader(
                for: texture,
                words: request.words,
                entryPoint: entryPoint,
                width: image.width,
                height: image.height,
                argumentFloats: (request.bytes.count + 3) / 4
            ) else { continue }

            shader.pipeline.update(ShaderUniforms(
                time: Float(Double(DispatchTime.now().uptimeNanoseconds - shader.started) / 1e9),
                frame: Float(shader.frame),
                resolutionX: Float(image.width),
                resolutionY: Float(image.height)
            ))
            shader.pipeline.updateArguments(bytes: request.bytes)
            shader.frame += 1
            engine.oneTimeSubmit { cmd in
                shader.container.needsRender = true
                shader.node.update(engine, slot: shader.container, cmd: cmd)
                copy(shader.node.image, into: image.image, width: image.width, height: image.height, cmd)
            }
            // `update` published the container, which is not composited.
            engine.readable.remove(shader.container.id)
            texture.shaderDidRender()
            rendered = true
        }
        guard rendered else { return }
        // A shader sampling one of those textures has new input, with no pass
        // to tell it — the same check `endPass` makes.
        for slot in slots.values {
            if slot.textureGenerations != slot.textures.generations {
                slot.textureGenerations = slot.textures.generations
                slot.container.needsRender = true
            }
            if let texture = slot.contentTexture, slot.contentGeneration != texture.generation {
                slot.contentGeneration = texture.generation
                slot.container.needsRender = true
            }
        }
    }

    /// The texture's shader node, rebuilt if the module, the size or the
    /// input's size outgrew what it was built for.
    private func textureShader(
        for texture: RenderTexture,
        words: [UInt32],
        entryPoint: String,
        width: Int,
        height: Int,
        argumentFloats: Int
    ) -> TextureShader? {
        let key = ObjectIdentifier(texture)
        if let existing = textureShaders[key] {
            if existing.words == words,
               existing.node.width == UInt32(width),
               existing.node.height == UInt32(height),
               existing.pipeline.argumentCapacity >= argumentFloats {
                return existing
            }
            // Its last submit was waited on; nothing else uses it.
            existing.destroy(engine)
            textureShaders[key] = nil
        }
        do {
            let image = try makeImage(width: width, height: height, usage: .storage)
            let node = ComputeShaderNode<N>(
                width: UInt32(width),
                height: UInt32(height),
                image: image.image,
                imageView: image.view,
                memory: image.memory
            )
            let pipeline: ShaderPipeline
            do {
                pipeline = try ShaderPipeline(
                    engine: engine,
                    imageView: image.view,
                    source: .spirv(words),
                    entryPoint: entryPoint,
                    argumentCapacity: argumentFloats == 0 ? 0 : max(256, argumentFloats * 3 / 2)
                )
            } catch {
                node.destroyResources(engine)
                throw error
            }
            node.computePipeline = pipeline.pipeline
            node.computeLayout = pipeline.pipelineLayout
            node.computeDescriptorSet = pipeline.descriptorSet
            let shader = TextureShader(
                texture: texture,
                words: words,
                node: node,
                pipeline: pipeline,
                container: N(id: Int.random(in: Int.min...Int.max), context: .compute(node))
            )
            textureShaders[key] = shader
            return shader
        } catch {
            nucleantLogError("NucleantUI: render(into:) build (\(width)x\(height)) failed: \(error)\n")
            return nil
        }
    }

    /// The shader's output into the texture's image, both left where their
    /// owners expect them: the output where the node's next dispatch starts
    /// from, the texture's where its placements and samplers read it.
    /// Both RGBA8, so a straight copy; both stored top-down.
    private func copy(_ source: VkImage, into destination: VkImage, width: Int, height: Int, _ cmd: VkCommandBuffer) {
        engineImageBarrier(
            cmd, image: source,
            srcLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            srcAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
            srcStage: VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            dstLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            dstAccess: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue),
            dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT
        )
        engineImageBarrier(
            cmd, image: destination,
            srcLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            srcAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
            srcStage: VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
            dstLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            dstAccess: VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue),
            dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT
        )
        let layers = VkImageSubresourceLayers(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            mipLevel: 0, baseArrayLayer: 0, layerCount: 1
        )
        var region = VkImageCopy()
        region.srcSubresource = layers
        region.dstSubresource = layers
        region.extent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        vkCmdCopyImage(
            cmd,
            source, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            destination, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1, &region
        )
        engineImageBarrier(
            cmd, image: destination,
            srcLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            srcAccess: VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue),
            srcStage: VK_PIPELINE_STAGE_TRANSFER_BIT,
            dstLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
            dstStage: VK_PIPELINE_STAGE_ALL_COMMANDS_BIT
        )
        engineImageBarrier(
            cmd, image: source,
            srcLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            srcAccess: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue),
            srcStage: VK_PIPELINE_STAGE_TRANSFER_BIT,
            dstLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
            dstStage: VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT
        )
    }

    // MARK: - Building

    /// Whether a slot gets a canvas, and if so which one to start from.
    private enum LayerRequest {
        case none
        /// A canvas to retarget if given, a spare or a fresh one otherwise.
        case reuse(Layer?)
        /// No layer: sample this canvas node's own image.
        case canvas(RenderNodeManager<N>.ThorCanvasNode)
        /// No layer: sample this `RenderTexture`'s own image.
        case texture(RenderTexture)
    }

    private func makeSlot(
        request: Request,
        arguments: ShaderArguments,
        argumentFloats: Int,
        textures: ShaderTextures,
        textureInputs: [ShaderImageInput],
        width: Int,
        height: Int,
        layer layerRequest: LayerRequest
    ) -> Slot? {
        let started = PerfTrace.isVerbose ? DispatchTime.now().uptimeNanoseconds : 0
        let layer: Layer?
        let canvas: RenderNodeManager<N>.ThorCanvasNode?
        let contentTexture: RenderTexture?
        let withLayer: Bool
        switch layerRequest {
        case .none:
            layer = nil
            canvas = nil
            contentTexture = nil
            withLayer = false
        case .reuse(let handed):
            guard let made = makeLayer(width: width, height: height, reusing: handed) else { return nil }
            layer = made
            canvas = nil
            contentTexture = nil
            withLayer = true
        case .canvas(let node):
            layer = nil
            canvas = node
            contentTexture = nil
            withLayer = false
        case .texture(let texture):
            layer = nil
            canvas = nil
            contentTexture = texture
            withLayer = false
        }
        // The image the shader samples as `uContent`: the layer's, the canvas
        // node's own, or the texture's. Borrowed in every case — whoever made
        // it owns and frees it.
        let input: (image: VkImage, view: VkImageView)? = layer.map { ($0.node.image, $0.node.imageView) }
            ?? canvas.map { ($0.node.image, $0.node.imageView) }
            ?? contentTexture?.gpuImage.map { ($0.image, $0.view) }
        let canvasReady = PerfTrace.isVerbose ? DispatchTime.now().uptimeNanoseconds : 0
        defer {
            PerfTrace.trace("shader slot \(width)x\(height)\(withLayer ? " +layer" : ""): "
                + "\(PerfTrace.millis(since: started))"
                + (withLayer ? " (canvas \(PerfTrace.millis(from: started, to: canvasReady)))" : ""))
        }
        do {
            // Room for half again as many floats as there are now, so an
            // array that grows a little does not rebuild the slot each time.
            let capacity = argumentFloats == 0 ? 0 : max(256, argumentFloats * 3 / 2)
            // What the slot runs: a compute module and its entry point, or a
            // vertex + fragment pair and what one draw covers. Compiled
            // before any GPU object is made, so a shader that does not
            // compile leaves nothing to clean up.
            let samplesContent = input != nil
            // A canvas node's image and a `RenderTexture`'s are both stored
            // top-down, unlike a layer drawn y-up.
            let contentIsTopDown = canvas != nil || contentTexture != nil
            var compute: (code: ShaderCode, entryPoint: String)?
            var graphics: (code: GraphicsShaderCode, draw: ShaderDraw)?
            switch request {
            case .compute(let function, _):
                compute = (try ShaderCode.compute(
                    function,
                    samplesContent: samplesContent,
                    contentIsTopDown: contentIsTopDown,
                    arguments: arguments,
                    textures: textures
                ), "main")
            case .graphics(let function, let draw, _):
                graphics = (try GraphicsShaderCode.graphics(
                    function,
                    samplesContent: samplesContent,
                    contentIsTopDown: contentIsTopDown,
                    arguments: arguments,
                    textures: textures
                ), draw)
            case .module(let words, let stages, let draw, _):
                if let vertex = stages.vertex, let fragment = stages.fragment {
                    graphics = (.spirv(words, vertexEntryPoint: vertex, fragmentEntryPoint: fragment), draw)
                } else if let entryPoint = stages.compute {
                    compute = (.spirv(words), entryPoint)
                } else {
                    throw ShaderError.compileFailed(
                        "the module has neither a compute entry point nor a vertex + fragment pair"
                    )
                }
            }
            let backend: Backend
            let context: N.Context
            if let compute {
                let image = try makeImage(width: width, height: height, usage: .storage)
                // Borrowed, as the node's contract says: the layer's node, the
                // canvas's, or the texture's owns the image and frees it. The
                // content comes first so binding 2 is written before 4 and up.
                let inputs = (input.map { [ShaderImageInput.content($0.view)] } ?? []) + textureInputs
                let node = ComputeShaderNode<N>(
                    width: UInt32(width),
                    height: UInt32(height),
                    image: image.image,
                    imageView: image.view,
                    memory: image.memory,
                    inputs: inputs
                )
                let pipeline = try ShaderPipeline(
                    engine: engine,
                    imageView: image.view,
                    inputs: inputs,
                    source: compute.code,
                    entryPoint: compute.entryPoint,
                    argumentCapacity: capacity
                )
                node.computePipeline = pipeline.pipeline
                node.computeLayout = pipeline.pipelineLayout
                node.computeDescriptorSet = pipeline.descriptorSet
                node.dirty = true
                backend = .compute(node, pipeline)
                context = .compute(node)
            } else if let graphics {
                let (code, draw) = graphics
                let pass = try colorPass()
                let image = try makeImage(width: width, height: height, usage: .colorAttachment)
                let node = try VertFragShaderNode<N>(
                    width: UInt32(width),
                    height: UInt32(height),
                    image: image.image,
                    imageView: image.view,
                    memory: image.memory,
                    pass: pass,
                    vertexCount: UInt32(draw.vertices),
                    instanceCount: UInt32(draw.instances)
                )
                let pipeline: VertexShaderPipeline
                do {
                    pipeline = try VertexShaderPipeline(
                        engine: engine,
                        renderPass: pass.renderPass!,
                        inputs: (input.map { [ShaderImageInput.content($0.view)] } ?? []) + textureInputs,
                        source: code,
                        argumentCapacity: capacity
                    )
                } catch {
                    node.destroyResources(engine)
                    throw error
                }
                node.pipeline = pipeline.pipeline
                node.pipelineLayout = pipeline.pipelineLayout
                node.descriptorSet = pipeline.descriptorSet
                node.dirty = true
                backend = .graphics(node, pipeline)
                context = .vertexShader(node)
            } else {
                // Every request above set one of the two or threw.
                return nil
            }

            let container = N(
                id: Int.random(in: Int.min...Int.max),
                context: context
            )
            container.observeContext()
            // After the layer's canvas node, so the engine draws the canvas
            // before the shader samples it.
            engine.append(container)

            return Slot(
                backend: backend,
                container: container,
                layer: layer,
                canvas: canvas,
                contentTexture: contentTexture,
                inputs: (input.map { [ShaderImageInput.content($0.view)] } ?? []) + textureInputs,
                width: width,
                height: height,
                request: request,
                arguments: arguments,
                textures: textures
            )
        } catch {
            nucleantLogError("NucleantUI: shader node build (\(width)x\(height)) failed: \(error)\n")
            if let layer {
                engine.nodes.removeAll { $0.id == layer.container.id }
                recycle(layer)
            }
            return nil
        }
    }

    /// The canvas half of a `.shader` slot: a canvas node the size of the
    /// view, in the engine's list so it is drawn each frame its content
    /// changed, but never composited — `compositesToWindow` is what keeps its
    /// image off the swapchain and its size off the window's.
    ///
    /// `reusing` (or a spare from the shared pool) is retargeted in place
    /// rather than rebuilt: the canvas keeps its renderer, gets a new image
    /// at the new size, and its slot keeps its identity in the engine.
    private func makeLayer(width: Int, height: Int, reusing handed: Layer?) -> Layer? {
        let acquired = renderNodes.acquire(width: width, height: height, reusing: handed)
        guard let layer = acquired else {
            return nil
        }
        layer.container.compositesToWindow = false
        return layer
    }

    /// Free one retired slot. The caller has already detached it from the
    /// engine and drained the device.
    ///
    /// The pipeline goes first: its descriptor set points at the node's image
    /// view, so nothing references the image by the time it is freed.
    /// `engine.remove(id:)` is deliberately *not* used — it frees the node's
    /// resources itself, and the slot is no longer in `engine.nodes` for it to
    /// find anyway.
    private func destroy(_ slot: Slot) {
        switch slot.backend {
        case .compute(let node, let pipeline):
            node.computePipeline = nil
            node.computeLayout = nil
            node.computeDescriptorSet = nil
            pipeline.destroy()
            node.destroyResources(engine)
        case .graphics(let node, let pipeline):
            node.pipeline = nil
            node.pipelineLayout = nil
            node.descriptorSet = nil
            pipeline.destroy()
            node.destroyResources(engine)
        }
        if let layer = slot.layer {
            recycle(layer)
        }
    }

    /// The render pass every `VertexShader` slot draws with — one per
    /// registry, made on first use; the format never varies.
    private var sharedColorPass: ColorAttachmentPass?

    private func colorPass() throws -> ColorAttachmentPass {
        if let sharedColorPass { return sharedColorPass }
        let pass = try ColorAttachmentPass(device: engine.device)
        sharedColorPass = pass
        return pass
    }

    /// How a slot's image is written.
    private enum ImageUsage {
        /// By a compute dispatch: `STORAGE`, left in GENERAL.
        case storage
        /// By a render pass: `COLOR_ATTACHMENT`, left in UNDEFINED for the
        /// pass to take from.
        case colorAttachment
    }

    /// Hand a canvas that is no longer in use back to the shared pool,
    /// emptied of its paints; past the pool's limit it is freed.
    private func recycle(_ layer: Layer) {
        renderNodes.recycle(layer)
    }

    /// The image a slot's shader writes and the composite samples.
    ///
    /// `VulkanCore.createStorageImage` does much of this, but it is a method on
    /// the `VulkanCore` bootstrap class rather than on `VulkanContext`, so it
    /// isn't reachable from the render engine. RGBA8 rather than BGRA8: storage
    /// support for it is universal, and the composite samples through a view so
    /// the channel order never has to match the swapchain's.
    private func makeImage(
        width: Int,
        height: Int,
        usage: ImageUsage
    ) throws -> (image: VkImage, view: VkImageView, memory: VkDeviceMemory) {
        var info = VkImageCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        info.imageType = VK_IMAGE_TYPE_2D
        info.format = VK_FORMAT_R8G8B8A8_UNORM
        info.extent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        info.mipLevels = 1
        info.arrayLayers = 1
        info.samples = VK_SAMPLE_COUNT_1_BIT
        info.tiling = VK_IMAGE_TILING_OPTIMAL
        // `TRANSFER_SRC` on every slot image, not just the ones read back
        // today: it costs nothing at creation, and without it a
        // shader-written image cannot be copied out at all — which is what
        // `tex.image()` and the texture-vs-`renderImage` test do.
        let readable = VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue
        switch usage {
        case .storage:
            info.usage = VkImageUsageFlags(
                VK_IMAGE_USAGE_STORAGE_BIT.rawValue | VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | readable
            )
        case .colorAttachment:
            info.usage = VkImageUsageFlags(
                VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | readable
            )
        }
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED

        var image: VkImage?
        guard vkCreateImage(engine.device, &info, nil, &image) == VK_SUCCESS, let image else {
            throw ShaderError.vulkan("vkCreateImage")
        }

        var requirements = VkMemoryRequirements()
        vkGetImageMemoryRequirements(engine.device, image, &requirements)

        var allocation = VkMemoryAllocateInfo()
        allocation.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        allocation.allocationSize = requirements.size
        allocation.memoryTypeIndex = engine.findMemoryType(
            typeFilter: requirements.memoryTypeBits,
            properties: VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        )

        var memory: VkDeviceMemory?
        guard vkAllocateMemory(engine.device, &allocation, nil, &memory) == VK_SUCCESS,
              let memory
        else {
            vkDestroyImage(engine.device, image, nil)
            throw ShaderError.vulkan("vkAllocateMemory")
        }
        vkBindImageMemory(engine.device, image, memory, 0)

        var viewInfo = VkImageViewCreateInfo()
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image = image
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format = VK_FORMAT_R8G8B8A8_UNORM
        viewInfo.subresourceRange = VkImageSubresourceRange(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1
        )

        var view: VkImageView?
        guard vkCreateImageView(engine.device, &viewInfo, nil, &view) == VK_SUCCESS,
              let view
        else {
            vkFreeMemory(engine.device, memory, nil)
            vkDestroyImage(engine.device, image, nil)
            throw ShaderError.vulkan("vkCreateImageView")
        }

        // UNDEFINED → GENERAL once, so the very first dispatch has somewhere
        // valid to write. `ComputeShaderNode.update` starts its barrier from
        // its tracked layout, which the node initialises to GENERAL. A colour
        // attachment needs no transition: its render pass starts from
        // UNDEFINED and clears.
        guard usage == .storage else { return (image, view, memory) }
        engine.oneTimeSubmit { cmd in
            engineImageBarrier(
                cmd,
                image: image,
                srcLayout: VK_IMAGE_LAYOUT_UNDEFINED,
                srcAccess: 0,
                srcStage: VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                dstLayout: VK_IMAGE_LAYOUT_GENERAL,
                dstAccess: VkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT.rawValue),
                dstStage: VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT
            )
        }

        return (image, view, memory)
    }
}
