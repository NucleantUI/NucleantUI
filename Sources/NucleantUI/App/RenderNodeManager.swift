//
//  RenderNodeManager.swift
//  NucleantUI
//
//  The render nodes that belong to *views*, kept alive across the momentary
//  view structs. A view pulls its node out of here by the identity its state
//  is keyed by, every pass it is placed; a node not pulled by the end of a
//  pass belongs to a view that left the tree, and is retired.
//
//  Three kinds of node, all the engine's. A canvas node (`CanvasNode`,
//  CanvasNode.swift) is a canvas the size of the view's frame that a display
//  list is drawn into — `.drawingGroup()`, the `.shader` layer canvases, and
//  the painter that fills the image nodes — in whichever backend the build
//  has (`CanvasBackend`: CanvasBackend+Skia.swift under `SKIA_MODE`,
//  CanvasBackend+Thor.swift otherwise). A `ThorCanvas` view's node is ThorVG
//  in every build, and kept apart (ThorCanvasNodes.swift). Canvases are
//  pooled on retirement: a fresh one is far dearer than one retargeted. An
//  image node (`ImageEntry`) is the engine's copy-target image, for the
//  automatic per-view nodes: microseconds to make, pooled by size.
//
//  What a node holds is the view's business (it draws into the node it
//  pulled); where its runs split around nested nodes is `RenderBoundaries`';
//  how an image node gets its pixels is `NodePainter`'s. This keeps the
//  nodes, sizes their images, and puts the engine's list in the order the
//  tree paints in.
//

import NucleantVulkan
import Dispatch

/// What a per-view node is keyed by: where the view stands, which view it is
/// (type and stamped call site), and — when the author asked to start over —
/// their own id.
struct RenderNodeKey: Hashable {
    let path: [Int]
    let identity: ViewIdentity
    /// `ThorCanvas(id:)`'s value, hashed; the view's `ViewID` hashed when none is given. A different
    /// value is a different node. For an automatic node, the run index: 0
    /// for the view's primary image, k for the run after its k-th nested
    /// node when that run needs an image of its own.
    let id: Int

    init(path: [Int], identity: ViewIdentity, id: Int = 0) {
        self.path = path
        self.identity = identity
        self.id = id
    }
}

@MainActor
final class RenderNodeManager {

    /// A standing automatic node: the engine's copy-target image, and what
    /// `NodePainter` knows it holds.
    @MainActor
    final class ImageEntry {
        let node: ImageNode<NucleantRenderNode>
        let container: NucleantRenderNode
        /// What the image holds, in the image's own coordinates; `nil` for a
        /// fresh or pooled image holding nothing of use.
        var content: DisplayList?
        /// What it should hold after this pass — set when the list differs
        /// from `content`, painted at the end of the pass.
        var pending: DisplayList?
        /// The part of the image `pending` changes, in the image's own
        /// coordinates (points), when the rest can be kept. `nil` paints
        /// the whole image.
        var damage: Rect?
        /// The window pixel the image's origin sits at — the content is
        /// relative to it, so a change of origin is a change of content.
        var pixelOrigin = SIMD2<Double>(0, 0)
        var used = true

        /// Pixel size of the image — a multiple of the granule.
        var width: Int { Int(node.width) }
        var height: Int { Int(node.height) }

        init(node: ImageNode<NucleantRenderNode>, container: NucleantRenderNode) {
            self.node = node
            self.container = container
        }
    }

    private unowned let engine: NucleantRenderEngine

    /// How this build's canvases are made — Skia's or ThorVG's.
    private let backend: CanvasBackend

    /// The `ThorCanvas` views' nodes, ThorVG in every build.
    private(set) lazy var thorCanvases = ThorCanvasNodes(engine: engine, manager: self)

    /// The canvas nodes standing, by the identity of the view that owns
    /// each; and the image nodes, by the view (and run) each holds.
    private var nodes: [RenderNodeKey: CanvasNode] = [:]
    private var images: [RenderNodeKey: ImageEntry] = [:]

    /// Backing-store pixels per point.
    var scale: Double = 1 {
        didSet {
            for node in nodes.values { node.renderer.scale = scale }
            thorCanvases.scale = scale
        }
    }

    /// The window's content size in points, per pass. An image is never
    /// bigger than the swapchain: the composite drops a viewport whose
    /// dimensions exceed it (found the hard way with a 912×624 overlay over
    /// a 900×620 window — a smaller viewport hanging past an edge is fine).
    /// A node larger than the window is composited through a window-sized
    /// image holding its visible part instead.
    private(set) var windowSize: Size = .zero

    /// Images are allocated in multiples of this many pixels per side: a
    /// 128×130 frame gets a 128×144 image, and growing to 128×140 reallocates
    /// nothing. `compositeRect` keeps the exact frame.
    static let granule = 16

    /// Canvases no longer in use, kept for the next node to appear — see the
    /// file comment for why a canvas is never thrown away lightly.
    private var spare: [CanvasNode] = []
    private let spareLimit = 12

    /// Images no longer in use, kept for the next node of the same size.
    private var spareImages: [ImageEntry] = []
    private let spareImageLimit = 32

    /// Retired this pass — detached from the engine, GPU objects still
    /// allocated until `releasePending` runs outside any recording.
    private var pendingDestroy: [CanvasNode] = []
    private var pendingDestroyImages: [ImageEntry] = []

    /// This pass's composite order, by container id — every node and shader
    /// slot placed this pass, numbered as it was placed. `endPass` sorts the
    /// engine's list by it.
    private var paintOrders: [Int: Int] = [:]
    private var paintCounter = 0

    init(engine: NucleantRenderEngine) {
        self.engine = engine
        self.backend = CanvasBackend(engine: engine)
    }

    // MARK: - Layout-pass lifecycle

    func beginPass(windowSize: Size) {
        self.windowSize = windowSize
        for node in nodes.values { node.used = false }
        for entry in images.values { entry.used = false }
        thorCanvases.beginPass()
        paintOrders.removeAll(keepingCapacity: true)
        paintCounter = 0
    }

    /// The next position in this pass's paint order. Taken by everything
    /// that composites — per-view nodes, shader slots — at the moment it is
    /// placed, which is tree paint order.
    func nextPaintOrder() -> Int {
        defer { paintCounter += 1 }
        return paintCounter
    }

    /// File `container` at `order` for this pass. `layer` puts a slot's
    /// canvas just before the compute node that samples it: the engine
    /// updates nodes in list order, so the canvas must be drawn first.
    func composite(_ container: NucleantRenderNode, at order: Int, layer: Bool = false) {
        paintOrders[container.id] = order * 2 + (layer ? 0 : 1)
    }

    /// Retire the nodes no view pulled this pass: their views left the tree.
    func retireUnused() {
        for (key, node) in nodes where !node.used {
            retire(node)
            nodes[key] = nil
        }
        for (key, entry) in images where !entry.used {
            retire(entry)
            images[key] = nil
        }
        thorCanvases.retireUnused()
    }

    /// Put the engine's list in this pass's paint order: the window canvas
    /// (and anything else not placed by a view) first, then every node and
    /// slot as it was placed. The engine composites in list order, later on
    /// top — so without this a node created later would sit over one that
    /// the tree draws after it.
    func endPass() {
        guard !paintOrders.isEmpty else { return }
        // Ranked once each, and by the current position second, so the
        // sort is stable whatever the standard library's happens to be.
        var ranked: [Ranked] = []
        ranked.reserveCapacity(engine.nodes.count)
        for (offset, node) in engine.nodes.enumerated() {
            ranked.append(Ranked(order: paintOrders[node.id] ?? -1, offset: offset, node: node))
        }
        ranked.sort()
        var changed = false
        for (offset, entry) in ranked.enumerated() where entry.offset != offset {
            changed = true
            break
        }
        if changed {
            engine.nodes = ranked.map(\.node)
        }
    }

    private struct Ranked: Comparable {
        let order: Int
        let offset: Int
        let node: NucleantRenderNode

        static func < (a: Ranked, b: Ranked) -> Bool {
            a.order != b.order ? a.order < b.order : a.offset < b.offset
        }

        static func == (a: Ranked, b: Ranked) -> Bool {
            a.order == b.order && a.offset == b.offset
        }
    }

    // MARK: - Image sizes

    /// Pixel size the image for `rect` is allocated at: rounded up to the
    /// granule, and never past the window (see `windowSize`).
    func imageSize(for rect: Rect) -> (width: Int, height: Int) {
        imageSize(pixelWidth: (rect.width * scale).rounded(.up), pixelHeight: (rect.height * scale).rounded(.up))
    }

    func imageSize(pixelWidth: Double, pixelHeight: Double) -> (width: Int, height: Int) {
        func round(_ pixels: Double, limit: Double) -> Int {
            let pixels = max(1, Int(pixels))
            let granule = Self.granule
            let rounded = (pixels + granule - 1) / granule * granule
            let cap = Int((limit * scale).rounded(.up))
            return cap > 0 ? max(1, min(rounded, max(cap, pixels))) : rounded
        }
        return (round(pixelWidth, limit: windowSize.width), round(pixelHeight, limit: windowSize.height))
    }

    /// `rect` in whole pixels, as a shader slot sizes its own image.
    func exactImageSize(for rect: Rect) -> (width: Int, height: Int) {
        (max(1, Int((rect.width * scale).rounded())), max(1, Int((rect.height * scale).rounded())))
    }

    // MARK: - Canvas nodes: by view, pool, build, retire, free

    /// The canvas node standing for `key`, resized if its frame outgrew the
    /// image (or left two granules of it spare), taken from the pool or
    /// built if there is none. Composited into its frame.
    func canvasNode(for key: RenderNodeKey, rect: Rect) -> CanvasNode? {
        let size = imageSize(for: rect)
        if let existing = nodes[key] {
            existing.used = true
            // An image a little bigger than the frame is kept — the scissor
            // cuts what it draws past the frame — so a frame animating
            // through sizes doesn't reallocate at every granule edge it
            // crosses. Never past the window, though: the composite drops a
            // viewport wider than the swapchain.
            let slack = 2 * Self.granule
            let cap = imageSize(for: Rect(origin: .zero, size: windowSize))
            if size.width <= existing.width, size.height <= existing.height,
               existing.width - size.width < slack, existing.height - size.height < slack,
               existing.width <= cap.width, existing.height <= cap.height {
                return existing
            }
            // Same node, new image — the display list is drawn again because
            // its frames changed with the size anyway.
            if resize(existing, width: size.width, height: size.height) {
                existing.content = nil
                existing.container.needsRender = true
                return existing
            }
            // Left at the old size, which is no use — replace it.
            retire(existing)
            nodes[key] = nil
        }
        guard let node = acquire(width: size.width, height: size.height) else { return nil }
        node.container.compositesToWindow = true
        nodes[key] = node
        return node
    }

    /// A canvas node at `width × height`, composited nowhere yet: a spare
    /// retargeted in place if there is one, else a fresh one. In the engine's
    /// list on return, holding no paints.
    func acquire(width: Int, height: Int) -> CanvasNode? {
        acquire(width: width, height: height, reusing: nil)
    }

    /// As `acquire(width:height:)`, starting from `handed` — a canvas its
    /// previous owner is passing straight on — before the pool.
    func acquire(width: Int, height: Int, reusing handed: CanvasNode?) -> CanvasNode? {
        if let node = handed ?? spare.popLast() {
            if resize(node, width: width, height: height) {
                node.renderer.scale = scale
                node.content = nil
                node.used = true
                node.container.needsRender = true
                engine.append(node.container)
                return node
            }
            // Left at its old size, which is no use here — replace it.
            destroy(node)
        }
        return makeCanvasNode(width: width, height: height)
    }

    /// The window's own canvas, filling the swapchain: the one the tree
    /// draws into wherever nothing gives a view a node of its own. Not kept
    /// here — the window holds it, and resizes it with `resize`.
    func makeWindowCanvas(width: Int, height: Int) -> CanvasNode? {
        makeCanvasNode(width: width, height: height)
    }

    /// A fresh canvas node at `width × height`, in the engine's list.
    private func makeCanvasNode(width: Int, height: Int) -> CanvasNode? {
        let started = PerfTrace.isVerbose ? DispatchTime.now().uptimeNanoseconds : 0
        guard let made = backend.makeCanvas(width: width, height: height) else { return nil }
        engine.append(made.container)
        made.renderer.scale = scale
        let node = CanvasNode(node: made.node, container: made.container, renderer: made.renderer, width: width, height: height)
        PerfTrace.trace("canvas node \(width)x\(height): \(PerfTrace.millis(since: started))")
        return node
    }

    /// Give the node an image of `width × height`, keeping its identity in
    /// the engine. False leaves it as it was.
    func resize(_ node: CanvasNode, width: Int, height: Int) -> Bool {
        guard backend.resize(node.node, id: node.container.id, width: width, height: height) else {
            return false
        }
        node.width = width
        node.height = height
        return true
    }

    /// Take a node out of the engine now and queue its GPU objects for
    /// `releasePending`. Freeing here, mid-pass, is the use-after-free the
    /// shader registry hit: command buffers in flight still reference the
    /// image. Taking it out of `engine.nodes` stops it compositing at once,
    /// which is all that has to happen now.
    func retire(_ node: CanvasNode) {
        engine.nodes.removeAll { $0.id == node.container.id }
        engine.invalidateComposite(id: node.container.id)
        pendingDestroy.append(node)
    }

    /// Free (or pool) everything retired since the last call. Called at the
    /// top of a frame, before anything is recorded; a node that is freed
    /// drains the device itself, one that is pooled needs no drain.
    func releasePending() {
        thorCanvases.releasePending()
        guard !pendingDestroy.isEmpty || !pendingDestroyImages.isEmpty else { return }
        let retired = pendingDestroy
        let retiredImages = pendingDestroyImages
        pendingDestroy.removeAll(keepingCapacity: true)
        pendingDestroyImages.removeAll(keepingCapacity: true)
        for node in retired { recycle(node) }
        for entry in retiredImages { recycle(entry) }
    }

    /// Keep a canvas for the next node to appear, emptied of what it held;
    /// past the limit it is freed.
    func recycle(_ node: CanvasNode) {
        guard spare.count < spareLimit else {
            destroy(node)
            return
        }
        backend.clear(node.node)
        node.content = nil
        spare.append(node)
    }

    func destroy(_ node: CanvasNode) {
        backend.destroy(node.node)
    }

    func destroyAll() {
        thorCanvases.destroyAll()
        for node in nodes.values { retire(node) }
        nodes.removeAll()
        for entry in images.values { retire(entry) }
        images.removeAll()
        releasePending()
        for node in spare { destroy(node) }
        spare.removeAll()
        for entry in spareImages { entry.node.destroyResources(engine) }
        spareImages.removeAll()
    }

    // MARK: - Image nodes: by view, pool, build, retire, free

    /// The standing image for `key` at `width × height`, or a new one when
    /// there is none or the content outgrew it. An image that is a granule
    /// bigger than needed is kept: content whose bounds hover around a
    /// granule edge would otherwise reallocate every other pass.
    func imageNode(for key: RenderNodeKey, width: Int, height: Int) -> ImageEntry? {
        if let existing = images[key] {
            existing.used = true
            let slack = 2 * Self.granule
            // Never past the window: the composite drops a viewport wider
            // than the swapchain, so an image the window has shrunk under
            // is replaced however little it exceeds it.
            let cap = imageSize(for: Rect(origin: .zero, size: windowSize))
            if width <= existing.width, height <= existing.height,
               existing.width - width < slack, existing.height - height < slack,
               existing.width <= cap.width, existing.height <= cap.height {
                return existing
            }
            retire(existing)
            images[key] = nil
        }
        guard let entry = acquireImage(width: width, height: height) else { return nil }
        images[key] = entry
        return entry
    }

    private func acquireImage(width: Int, height: Int) -> ImageEntry? {
        if let index = spareImages.firstIndex(where: { $0.width == width && $0.height == height }) {
            let entry = spareImages.remove(at: index)
            entry.used = true
            engine.append(entry.container)
            return entry
        }
        let node: ImageNode<NucleantRenderNode>
        do {
            node = try backend.makeImageNode(width: width, height: height)
        } catch {
            nucleantFlushStandardOutput()
            nucleantLogError("NucleantUI: image node (\(width)x\(height)) failed: \(error)\n")
            return nil
        }
        let container = NucleantRenderNode(id: Int.random(in: Int.min...Int.max), context: .image(node))
        container.observeContext()
        // Nothing to draw at frame time; the composite samples it once
        // `readable` says the first copy landed.
        container.needsRender = false
        engine.append(container)
        return ImageEntry(node: node, container: container)
    }

    /// As `retire(_:)` for canvas nodes: out of the engine now, freed or
    /// pooled at `releasePending`.
    private func retire(_ entry: ImageEntry) {
        engine.nodes.removeAll { $0.id == entry.container.id }
        engine.invalidateComposite(id: entry.container.id)
        entry.pending = nil
        entry.damage = nil
        // A copy not yet recorded would land in an image about to be freed.
        entry.node.pendingCopy = nil
        pendingDestroyImages.append(entry)
    }

    private func recycle(_ entry: ImageEntry) {
        entry.content = nil
        entry.pending = nil
        entry.damage = nil
        guard spareImages.count < spareImageLimit else {
            entry.node.destroyResources(engine)
            return
        }
        spareImages.append(entry)
    }
}
