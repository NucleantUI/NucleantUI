//
//  CanvasBackend+Thor.swift
//  NucleantUI
//
//  The ThorVG build (no `SKIA_MODE`): every `CanvasNode` — the window's,
//  `.drawingGroup()`'s, a `.shader` layer's, the painter's — is a ThorVG
//  canvas drawn by a `ThorDisplayRenderer`. CanvasBackend+Skia.swift defines
//  the same names for the Skia build; exactly one of the two is compiled,
//  and nothing that uses them says which.
//
//  A fresh wg canvas costs ~60ms (its renderer compiles pipelines on first
//  target), a retargeted one under a millisecond — which is why the node
//  manager pools retired canvases rather than freeing them.
//

#if !SKIA_MODE

import NucleantVulkan
import NucleantThorVG

/// What draws the views' display list in this build.
public typealias DisplayRenderer = ThorDisplayRenderer

/// How a canvas node is built, resized, emptied and freed with ThorVG.
@MainActor
final class CanvasBackend {
    typealias Node = ThorShaderNode<NucleantRenderNode>

    private unowned let engine: NucleantRenderEngine

    init(engine: NucleantRenderEngine) {
        self.engine = engine
    }

    /// A fresh canvas at `width × height` and its engine container — not yet
    /// in the engine's list — with a renderer drawing into it.
    func makeCanvas(width: Int, height: Int) -> (node: Node, container: NucleantRenderNode, renderer: DisplayRenderer)? {
        guard let node = engine.makeThorWidgetNode(width: width, height: height) else {
            // The engine reports *why* on stdout, which is fully buffered when
            // the process isn't attached to a terminal — flush it so the
            // reason lands next to this line rather than being lost.
            nucleantFlushStandardOutput()
            nucleantLogError("NucleantUI: ThorVG canvas build (\(width)x\(height)) failed\n")
            return nil
        }
        let container = NucleantRenderNode(id: Int.random(in: Int.min...Int.max), context: .thor(node))
        container.observeContext()
        return (node, container, ThorDisplayRenderer(canvas: node.canvas.base))
    }

    /// Retarget the canvas at an image of `width × height` — the same
    /// `Tvg_Canvas`, so its paints survive. False leaves it as it was.
    func resize(_ node: Node, id: Int, width: Int, height: Int) -> Bool {
        engine.resizeThorNode(node, id: id, width: width, height: height)
    }

    /// Empty a canvas going back to the pool: its paints come off.
    func clear(_ node: Node) {
        _ = tvg_canvas_remove(node.canvas.base, nil)
    }

    /// The canvas first: ThorVG holds its own reference to the wgpu texture
    /// behind the node's image for as long as it is the canvas's target, and
    /// the node's teardown releases that texture last.
    func destroy(_ node: Node) {
        _ = tvg_canvas_destroy(node.canvas.base)
        node.destroyResources(engine)
    }

    /// The copy-target image an automatic per-view node holds, in the
    /// engine's own format, which the ThorVG painter's image shares.
    func makeImageNode(width: Int, height: Int) throws -> ImageNode<NucleantRenderNode> {
        try engine.makeImageNode(width: width, height: height)
    }
}

#endif
