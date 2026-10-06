//
//  ThorCanvasNodes.swift
//  NucleantUI
//
//  The nodes behind `ThorCanvas` views. A `ThorCanvas` hands the author a
//  ThorVG canvas to fill with their own paints, so its node is ThorVG in
//  every build — unlike a `CanvasNode`, which draws the views' display list
//  through whichever backend the build has (CanvasBackend+Skia.swift /
//  CanvasBackend+Thor.swift).
//
//  Kept by `RenderNodeManager` alongside its canvas nodes: pulled by key each
//  pass, retired when no view pulled them, pooled on release — a fresh wg
//  canvas costs ~60ms, a retargeted one under a millisecond.
//

import NucleantVulkan
import NucleantThorVG
import Dispatch

extension RenderNodeManager {

    /// One `ThorCanvas` view's ThorVG canvas, the size of its frame,
    /// composited into it — or, under a `.shader`, sampled as the effect's
    /// input instead.
    @MainActor
    final class ThorCanvasNode {
        let node: ThorShaderNode<NucleantRenderNode>
        let container: NucleantRenderNode
        /// The canvas as the view's closures see it.
        let thorContext: ThorContext
        /// Pixel size of the image — the frame rounded up to whole granules,
        /// and kept while the frame fits with under two granules spare, so a
        /// frame that jitters or animates keeps its image.
        var width: Int
        var height: Int
        /// Whether `onInit` has run on this canvas, which build's `renderer`
        /// last ran, and the frame it ran for.
        var initialized = false
        var generation = -1
        var renderedSize: Size = .zero
        /// State the `renderer` closure read, each slot listing the view's
        /// path (`readerPath`) among its readers — undone before it runs
        /// again and when the node retires.
        var reads: [any AnyStateStorage] = []
        var readerPath: [Int] = []
        /// Seen during the current layout pass.
        var used = true
        /// Where the view was last placed, in points, and that origin snapped
        /// to a whole pixel: where the image actually composites.
        var rect: Rect = .zero
        var pixelOrigin: Point = .zero

        init(node: ThorShaderNode<NucleantRenderNode>, container: NucleantRenderNode, width: Int, height: Int) {
            self.node = node
            self.container = container
            self.thorContext = ThorContext(base: node.canvas.base)
            self.width = width
            self.height = height
        }

        /// Point the node at its frame, and at whatever its container lets
        /// it show. `scale` is pixels per point.
        func place(rect: Rect, clip: Rect?, scale: Double) {
            self.rect = rect
            // Whole pixels, at the image's own size, so texels map 1:1. The
            // image is bigger than the frame (the granule); the scissor below
            // cuts the slack.
            let x = (rect.minX * scale).rounded(.down)
            let y = (rect.minY * scale).rounded(.down)
            pixelOrigin = Point(x: x / scale, y: y / scale)
            container.compositeRect = SIMD4(x, y, Double(width), Double(height))
            let visible = clip.map { rect.intersection($0) } ?? rect
            let minX = (visible.minX * scale).rounded(.down)
            let minY = (visible.minY * scale).rounded(.down)
            let maxX = (visible.maxX * scale).rounded(.up)
            let maxY = (visible.maxY * scale).rounded(.up)
            container.compositeScissor = SIMD4(minX, minY, max(0, maxX - minX), max(0, maxY - minY))
        }

        /// Have the engine rasterize the canvas at the frame after its
        /// paints were changed in place: ThorVG re-prepares only what it is
        /// told changed, and `draw` alone is not guaranteed to ask.
        func rasterize() {
            _ = thorContext.update()
            if PerfTrace.isEnabled { PerfTrace.nodesDrawn += 1 }
            node.dirty = true
            container.needsRender = true
        }
    }

    /// The `ThorCanvas` nodes standing, by view; the spare pool; and what
    /// waits to be freed.
    @MainActor
    final class ThorCanvasNodes {
        private unowned let engine: NucleantRenderEngine
        private unowned let manager: RenderNodeManager

        private var nodes: [RenderNodeKey: ThorCanvasNode] = [:]
        private var spare: [ThorCanvasNode] = []
        private let spareLimit = 12
        private var pendingDestroy: [ThorCanvasNode] = []

        /// Backing-store pixels per point.
        var scale: Double = 1 {
            didSet {
                for node in nodes.values { node.thorContext.scale = scale }
            }
        }

        init(engine: NucleantRenderEngine, manager: RenderNodeManager) {
            self.engine = engine
            self.manager = manager
        }

        // MARK: Pass lifecycle

        func beginPass() {
            for node in nodes.values { node.used = false }
        }

        func retireUnused() {
            for (key, node) in nodes where !node.used {
                retire(node)
                nodes[key] = nil
            }
        }

        // MARK: By view

        /// The node standing for `key`, resized if its frame outgrew the
        /// image (or left two granules of it spare), taken from the pool or
        /// built if there is none. Composited into its frame.
        ///
        /// `exactSize` sizes the image to the frame's pixels and nothing more
        /// — for a node whose image a `.shader` samples as the view itself,
        /// where spare pixels past the frame would be part of what it samples.
        func node(for key: RenderNodeKey, rect: Rect, exactSize: Bool = false) -> ThorCanvasNode? {
            let size = exactSize ? manager.exactImageSize(for: rect) : manager.imageSize(for: rect)
            if let existing = nodes[key] {
                existing.used = true
                if exactSize {
                    if existing.width == size.width, existing.height == size.height {
                        return existing
                    }
                } else {
                    // An image a little bigger than the frame is kept — the
                    // scissor cuts what it draws past the frame — so a frame
                    // animating through sizes doesn't reallocate at every
                    // granule edge it crosses. Never past the window, though:
                    // the composite drops a viewport wider than the swapchain.
                    let slack = 2 * RenderNodeManager.granule
                    let cap = manager.imageSize(for: Rect(origin: .zero, size: manager.windowSize))
                    if size.width <= existing.width, size.height <= existing.height,
                       existing.width - size.width < slack, existing.height - size.height < slack,
                       existing.width <= cap.width, existing.height <= cap.height {
                        return existing
                    }
                }
                // Same node, new image — the canvas keeps its paints, so an
                // author's shapes survive.
                if resize(existing, width: size.width, height: size.height) {
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

        // MARK: Pool, build, retire, free

        /// A node at `width × height`, composited nowhere yet: a spare
        /// retargeted in place if there is one, else a fresh one. In the
        /// engine's list on return, holding no paints.
        private func acquire(width: Int, height: Int) -> ThorCanvasNode? {
            if let node = spare.popLast() {
                if resize(node, width: width, height: height) {
                    node.thorContext.scale = scale
                    node.initialized = false
                    node.generation = -1
                    node.renderedSize = .zero
                    node.used = true
                    node.container.needsRender = true
                    engine.append(node.container)
                    return node
                }
                // Left at its old size, which is no use here — replace it.
                destroy(node)
            }
            let started = PerfTrace.isVerbose ? DispatchTime.now().uptimeNanoseconds : 0
            guard let thor = engine.makeThorWidgetNode(width: width, height: height) else {
                nucleantFlushStandardOutput()
                nucleantLogError("NucleantUI: ThorCanvas node build (\(width)x\(height)) failed\n")
                return nil
            }
            let container = NucleantRenderNode(id: Int.random(in: Int.min...Int.max), context: .thor(thor))
            container.observeContext()
            engine.append(container)
            let node = ThorCanvasNode(node: thor, container: container, width: width, height: height)
            node.thorContext.scale = scale
            PerfTrace.trace("ThorCanvas node \(width)x\(height): \(PerfTrace.millis(since: started))")
            return node
        }

        /// Retarget the node's canvas at an image of `width × height` — the
        /// same `Tvg_Canvas`, so its paints survive. False leaves it as it was.
        private func resize(_ node: ThorCanvasNode, width: Int, height: Int) -> Bool {
            guard engine.resizeThorNode(node.node, id: node.container.id, width: width, height: height) else {
                return false
            }
            node.width = width
            node.height = height
            return true
        }

        /// Out of the engine now; freed or pooled at `releasePending`, outside
        /// any recording — command buffers in flight still reference its image.
        private func retire(_ node: ThorCanvasNode) {
            engine.nodes.removeAll { $0.id == node.container.id }
            engine.invalidateComposite(id: node.container.id)
            pendingDestroy.append(node)
        }

        func releasePending() {
            guard !pendingDestroy.isEmpty else { return }
            let retired = pendingDestroy
            pendingDestroy.removeAll(keepingCapacity: true)
            for node in retired { recycle(node) }
        }

        /// Keep a canvas for the next node to appear, emptied of its paints
        /// and of the reader registrations its `renderer` made; past the
        /// limit it is freed.
        private func recycle(_ node: ThorCanvasNode) {
            for storage in node.reads {
                storage.readers.removeValue(forKey: node.readerPath)
            }
            node.reads.removeAll()
            node.generation = -1
            node.renderedSize = .zero
            guard spare.count < spareLimit else {
                destroy(node)
                return
            }
            _ = tvg_canvas_remove(node.node.canvas.base, nil)
            node.initialized = false
            spare.append(node)
        }

        /// The canvas first: ThorVG holds its own reference to the wgpu
        /// texture behind the node's image for as long as it is the canvas's
        /// target, and the node's teardown releases that texture last.
        private func destroy(_ node: ThorCanvasNode) {
            _ = tvg_canvas_destroy(node.node.canvas.base)
            node.node.destroyResources(engine)
        }

        func destroyAll() {
            for node in nodes.values { retire(node) }
            nodes.removeAll()
            releasePending()
            for node in spare { destroy(node) }
            spare.removeAll()
        }
    }
}
