//
//  CanvasNode.swift
//  NucleantUI
//
//  A canvas the views' display list is drawn into: the window's, a
//  `.drawingGroup()`'s, a `.shader` layer's, the painter's. Which library
//  draws it is the build's — `CanvasBackend.Node` and `DisplayRenderer` are
//  Skia's under `SKIA_MODE` (CanvasBackend+Skia.swift) and ThorVG's otherwise
//  (CanvasBackend+Thor.swift). Nothing here names either.
//
//  `ThorCanvas` views are not drawn through these: an author's ThorVG paints
//  need a ThorVG canvas whatever the build, which is `ThorCanvasNode`.
//

import NucleantVulkan

extension RenderNodeManager {

    /// One canvas the size of a view's frame, composited into it — or, for a
    /// `.shader` layer and the painter, sampled or copied by another node
    /// instead of composited.
    @MainActor
    final class CanvasNode {
        let node: CanvasBackend.Node
        let container: NucleantRenderNode
        let renderer: DisplayRenderer
        /// Pixel size of the image — the frame rounded up to whole granules,
        /// and kept while the frame fits with under two granules spare, so a
        /// frame that jitters or animates keeps its image.
        var width: Int
        var height: Int
        /// What the canvas holds: node-local for a drawing group, absolute for
        /// a `.shader` layer — and for the latter, the origin it was drawn
        /// from. An identical list is not drawn again.
        var content: DisplayList?
        var origin: Point = .zero
        /// Seen during the current layout pass. Anything not seen has left
        /// the tree and is retired.
        var used = true
        /// Where the view was last placed, in points, and that origin snapped
        /// to a whole pixel: where the image actually composites, so texels
        /// land on pixels (a fractional origin bilinearly blurs everything).
        var rect: Rect = .zero
        var pixelOrigin: Point = .zero

        init(node: CanvasBackend.Node, container: NucleantRenderNode, renderer: DisplayRenderer, width: Int, height: Int) {
            self.node = node
            self.container = container
            self.renderer = renderer
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
            // The frame — from the snapped origin to the last pixel it touches —
            // intersected with the container's clip, as a shader slot's is.
            let visible = clip.map { rect.intersection($0) } ?? rect
            let minX = (visible.minX * scale).rounded(.down)
            let minY = (visible.minY * scale).rounded(.down)
            let maxX = (visible.maxX * scale).rounded(.up)
            let maxY = (visible.maxY * scale).rounded(.up)
            container.compositeScissor = SIMD4(minX, minY, max(0, maxX - minX), max(0, maxY - minY))
            if LayoutTrace.isEnabled {
                nucleantLogError(String(
                    format: "[layout] node    rect x=%7.2f y=%7.2f w=%7.2f h=%7.2f  image %dx%d\n",
                    rect.minX, rect.minY, rect.width, rect.height, width, height
                ))
            }
        }

        /// Draw `list` into the canvas — unless it is what the canvas already
        /// holds — for the engine to rasterize at the frame.
        func render(_ list: DisplayList, at path: [Int]) {
            guard content != list else { return }
            if PerfTrace.isEnabled { PerfTrace.nodesDrawn += 1 }
            PerfTrace.trace("node \(width)x\(height) at \(path): \(list.commands.count) commands drawn")
            renderer.render(list)
            content = list
            markDirty()
        }

        /// Have the engine draw the canvas again at the next frame.
        func markDirty() {
            node.dirty = true
            container.needsRender = true
        }
    }
}
