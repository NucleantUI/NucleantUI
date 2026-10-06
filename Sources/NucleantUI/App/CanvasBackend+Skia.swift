//
//  CanvasBackend+Skia.swift
//  NucleantUI
//
//  The Skia build (`SKIA_MODE`): every `CanvasNode` — the window's,
//  `.drawingGroup()`'s, a `.shader` layer's, the painter's — is a Skia node
//  drawn by a `SkiaDisplayRenderer`. CanvasBackend+Thor.swift defines the
//  same names for the ThorVG build; exactly one of the two is compiled, and
//  nothing that uses them says which.
//
//  Every node shares one Ganesh context, made with the first, so Skia's
//  caches (glyphs, pipelines) are built once for the window rather than once
//  per node.
//

#if SKIA_MODE

import CVulkan
import NucleantVulkan
import NucleantSkia

/// What draws the views' display list in this build.
public typealias DisplayRenderer = SkiaDisplayRenderer

/// How a canvas node is built, resized, emptied and freed with Skia.
@MainActor
final class CanvasBackend {
    typealias Node = SkiaShaderNode<NucleantRenderNode>

    private unowned let engine: NucleantRenderEngine

    /// The Ganesh context every node draws through, made with the first.
    private var context: SkiaVulkanContext?

    init(engine: NucleantRenderEngine) {
        self.engine = engine
    }

    /// The shared context, made on first use.
    private func sharedContext() -> SkiaVulkanContext? {
        if let context { return context }
        do {
            let made = try engine.makeSkiaContext()
            context = made
            return made
        } catch {
            nucleantFlushStandardOutput()
            nucleantLogError("NucleantUI: Skia context failed: \(error)\n")
            return nil
        }
    }

    /// A fresh node at `width × height` and its engine container — not yet
    /// in the engine's list — with a renderer drawing into it.
    func makeCanvas(width: Int, height: Int) -> (node: Node, container: NucleantRenderNode, renderer: DisplayRenderer)? {
        guard let context = sharedContext(),
              let node = engine.makeSkiaWidgetNode(context: context, width: width, height: height) else {
            nucleantFlushStandardOutput()
            nucleantLogError("NucleantUI: Skia canvas build (\(width)x\(height)) failed\n")
            return nil
        }
        let container = NucleantRenderNode(id: Int.random(in: Int.min...Int.max), context: .skia(node))
        container.observeContext()
        return (node, container, SkiaDisplayRenderer(node: node))
    }

    /// A new, empty surface at `width × height` for the same node. False
    /// leaves it as it was.
    func resize(_ node: Node, id: Int, width: Int, height: Int) -> Bool {
        engine.resizeSkiaNode(node, id: id, width: width, height: height)
    }

    /// Empty a node going back to the pool. A Skia surface keeps no paints
    /// — each list is drawn from a clear — so there is nothing to take off.
    func clear(_ node: Node) {}

    func destroy(_ node: Node) {
        node.destroyResources(engine)
    }

    /// The copy-target image an automatic per-view node holds. Its pixels
    /// are copied out of the painter's Skia image, which is RGBA and read as
    /// RGBA — the copy is bytes, so this one is the same.
    func makeImageNode(width: Int, height: Int) throws -> ImageNode<NucleantRenderNode> {
        try engine.makeImageNode(
            width: width, height: height,
            format: VK_FORMAT_R8G8B8A8_UNORM, viewFormat: VK_FORMAT_R8G8B8A8_UNORM
        )
    }
}

#endif
