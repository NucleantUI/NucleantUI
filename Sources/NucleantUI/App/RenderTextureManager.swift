//
//  RenderTextureManager.swift
//  NucleantUI
//
//  The GPU side of `RenderTexture`: the canvas each texture draws into, and
//  the container nodes that show one in the tree.
//
//  Two lifetimes meet here, and they are not the same one. A `RenderTexture`
//  is a Swift object a data model holds — nothing in the view tree owns it,
//  nothing retires it when a view goes away — so its canvas is held here
//  against a *weak* reference to the texture, and recycled at the top of a
//  frame once the texture itself is gone. Detach now, free later, as
//  everywhere else: freeing GPU objects inside a pass is the use-after-free
//  §8 fixed for teardown.
//
//  A *placement* is the other lifetime: one container per `tex.view()` in the
//  tree, keyed and retired by the pass the way `TextureNodeManager` keeps a
//  `TextureView`'s node. Every placement of one texture borrows the one
//  image — the texture owns it, and frees it once however many are showing
//  it.
//

import CVulkan
import NucleantVulkan

@MainActor
final class RenderTextureManager {

    private unowned let engine: NucleantRenderEngine
    /// For the canvas pool, the paint order and the composite bookkeeping —
    /// the same ones every other per-view node goes through.
    private unowned let renderNodes: RenderNodeManager

    /// One live texture's canvas. `texture` is weak: the texture is the
    /// owner, and its going away is what releases this.
    private struct Backing {
        weak var texture: RenderTexture?
        let canvas: RenderNodeManager.CanvasNode
    }

    private var backings: [Backing] = []

    /// One `tex.view()`'s container: a borrowed image composited into a rect.
    @MainActor
    final class Placement {
        let node: RenderTextureNode
        let container: NucleantRenderNode
        /// The image view the engine's composite descriptor set was built
        /// with — it caches per slot id, so a changed handle has to invalidate
        /// it rather than just being written here.
        var boundView: VkImageView
        /// Seen during the current pass. Anything not seen has left the tree.
        var used = true

        init(node: RenderTextureNode, container: NucleantRenderNode) {
            self.node = node
            self.container = container
            self.boundView = node.imageView
        }
    }

    private var placements: [RenderNodeKey: Placement] = [:]

    /// Retired this pass — out of the engine's list, freed at
    /// `releasePending`, outside any recording.
    private var pendingDestroy: [Placement] = []

    /// Renders asked for during a layout pass, run at `endPass`.
    private var queued: [@MainActor () -> Void] = []

    init(engine: NucleantRenderEngine, renderNodes: RenderNodeManager) {
        self.engine = engine
        self.renderNodes = renderNodes
    }

    // MARK: - Backings

    /// A canvas for `texture` at `width × height` pixels, drawn at `scale`
    /// pixels per point.
    ///
    /// Pooled like a `.shader` layer's: the first canvas in a process costs
    /// its backend's first-target compile, every one after it is a retarget.
    /// Never composited to the window — a texture is shown through its
    /// placements, or sampled by a shader, and never by being a node of its
    /// own in the swapchain.
    func makeBacking(
        for texture: RenderTexture,
        width: Int,
        height: Int,
        scale: Double
    ) -> RenderNodeManager.CanvasNode? {
        guard let canvas = renderNodes.acquire(width: width, height: height) else {
            nucleantLogError("NucleantUI: render texture canvas (\(width)x\(height)) failed\n")
            return nil
        }
        canvas.container.compositesToWindow = false
        // The texture's own scale, not the window's — and `RenderNodeManager`
        // leaves this canvas alone when the display scale changes, because it
        // is not one of its per-view nodes.
        canvas.renderer.scale = scale
        backings.append(Backing(texture: texture, canvas: canvas))
        return canvas
    }

    // MARK: - Placements

    /// The container showing `texture` at `key`, placed at `rect` (points)
    /// and cut to `clip`, in this pass's paint order. Made if the view is
    /// new, re-pointed if the texture has a different image than it was
    /// bound to.
    ///
    /// The texture's canvas is deliberately *not* filed in the paint order:
    /// `RenderNodeManager.endPass` ranks anything unplaced `-1`, which puts
    /// it before every placement and before any shader sampling it — written
    /// first, read after, in the same frame.
    @discardableResult
    func place(key: RenderNodeKey, texture: RenderTexture, rect: Rect, clip: Rect?) -> Placement? {
        guard let image = texture.gpuImage else { return nil }
        let scale = renderNodes.scale
        let placement: Placement

        if let existing = placements[key] {
            placement = existing
            placement.used = true
            if placement.boundView != image.view {
                placement.node.rebind(
                    image: image.image,
                    imageView: image.view,
                    width: UInt32(image.width),
                    height: UInt32(image.height)
                )
                placement.boundView = image.view
                // The engine caches a composite descriptor set per slot id and
                // never re-reads the image view for one it already has.
                engine.invalidateComposite(id: placement.container.id)
            }
        } else {
            let node = RenderTextureNode(
                width: UInt32(image.width),
                height: UInt32(image.height),
                image: image.image,
                imageView: image.view
            )
            let container = NucleantRenderNode(
                id: Int.random(in: Int.min...Int.max),
                context: .renderTexture(node)
            )
            container.observeContext()
            engine.append(container)
            placement = Placement(node: node, container: container)
            placements[key] = placement
        }

        placement.node.hasContent = texture.hasContent
        placement.container.needsRender = true
        position(placement, rect: rect, clip: clip, scale: scale)
        renderNodes.composite(placement.container, at: renderNodes.nextPaintOrder())
        return placement
    }

    /// Point the container at the frame: origin snapped to a whole pixel so
    /// texels land on pixels, the image mapped across the frame, and a
    /// scissor cutting it to whatever clips the view.
    ///
    /// The image is mapped to the *frame*, not drawn at its own pixel size:
    /// a texture placed in a smaller or larger frame is scaled by the
    /// composite, which is what lets `tex.view().resizable()` work at no
    /// cost. `RenderTextureContent` is what decides the frame.
    private func position(_ placement: Placement, rect: Rect, clip: Rect?, scale: Double) {
        let x = (rect.minX * scale).rounded(.down)
        let y = (rect.minY * scale).rounded(.down)
        placement.container.compositeRect = SIMD4(
            x, y,
            (rect.width * scale).rounded(),
            (rect.height * scale).rounded()
        )
        let visible = clip.map { rect.intersection($0) } ?? rect
        let minX = (visible.minX * scale).rounded(.down)
        let minY = (visible.minY * scale).rounded(.down)
        let maxX = (visible.maxX * scale).rounded(.up)
        let maxY = (visible.maxY * scale).rounded(.up)
        placement.container.compositeScissor = SIMD4(minX, minY, max(0, maxX - minX), max(0, maxY - minY))
    }

    // MARK: - Lifecycle

    func beginPass() {
        for placement in placements.values { placement.used = false }
    }

    /// A render asked for from inside a layout pass, to be run at the end of
    /// it. One tree at a time: rendering a texture during the window's walk
    /// would nest a pass inside a pass.
    func queue(_ work: @escaping @MainActor () -> Void) {
        queued.append(work)
    }

    /// Every placement showing `texture` now has content to composite. A
    /// render queued from inside a pass lands after the placements were put
    /// down, so they were told what was true before it.
    func textureDidRender(_ texture: RenderTexture) {
        guard let image = texture.gpuImage else { return }
        for placement in placements.values where placement.boundView == image.view {
            placement.node.hasContent = texture.hasContent
            placement.container.needsRender = true
        }
    }

    /// Run the renders this pass asked for, then retire the placements no
    /// view put down.
    func endPass() {
        if !queued.isEmpty {
            let work = queued
            queued.removeAll(keepingCapacity: true)
            for render in work { render() }
        }
        for (key, placement) in placements where !placement.used {
            retire(placement)
            placements[key] = nil
        }
    }

    private func retire(_ placement: Placement) {
        let id = placement.container.id
        engine.nodes.removeAll { $0.id == id }
        engine.invalidateComposite(id: id)
        pendingDestroy.append(placement)
    }

    /// Free what was retired, and recycle the canvas of every texture that
    /// has been released since the last frame. At the top of a frame, before
    /// anything is recorded — and before `RenderNodeManager.releasePending`,
    /// so a canvas handed back here reaches the pool in the same frame.
    func releasePending() {
        if !pendingDestroy.isEmpty {
            let retired = pendingDestroy
            pendingDestroy.removeAll(keepingCapacity: true)
            for placement in retired {
                // Frees nothing of its own — the image was the texture's. The
                // container is already out of the engine's list.
                placement.node.destroyResources(engine)
            }
        }
        guard backings.contains(where: { $0.texture == nil }) else { return }
        for backing in backings where backing.texture == nil {
            renderNodes.retire(backing.canvas)
        }
        backings.removeAll { $0.texture == nil }
    }

    func destroyAll() {
        for placement in placements.values { retire(placement) }
        placements.removeAll()
        for backing in backings { renderNodes.retire(backing.canvas) }
        backings.removeAll()
        releasePending()
    }
}

// MARK: - Readback

extension RenderTextureManager {

    /// `texture`'s pixels, copied out of its image into a `RasterImage`.
    ///
    /// Blocking and ours: `engine.device`, `findMemoryType` and
    /// `oneTimeSubmit` are the whole of what this needs, so it is written here
    /// rather than added to the engine's API. `nil` until the engine has
    /// actually drawn the texture's canvas — `engine.readable` carries that,
    /// and it is also what makes the layout the barrier starts from true
    /// (a thor node's update leaves its image in `SHADER_READ_ONLY_OPTIMAL`
    /// and publishes it in the same breath).
    func readback(of texture: RenderTexture) -> RasterImage? {
        guard let image = texture.gpuImage,
              let id = texture.canvasID,
              engine.readable.contains(id)
        else { return nil }

        let width = image.width, height = image.height
        let byteCount = width * height * 4
        guard byteCount > 0, let host = makeHostBuffer(byteCount: byteCount) else { return nil }
        defer {
            vkUnmapMemory(engine.device, host.memory)
            vkDestroyBuffer(engine.device, host.buffer, nil)
            vkFreeMemory(engine.device, host.memory, nil)
        }

        engine.oneTimeSubmit { cmd in
            engineImageBarrier(
                cmd,
                image: image.image,
                srcLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                srcAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
                srcStage: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                dstLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                dstAccess: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue),
                dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT
            )
            var region = VkBufferImageCopy()
            region.imageSubresource = VkImageSubresourceLayers(
                aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
                mipLevel: 0, baseArrayLayer: 0, layerCount: 1
            )
            region.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
            vkCmdCopyImageToBuffer(
                cmd, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, host.buffer, 1, &region
            )
            // Back where the node's own tracking believes it is, or the next
            // frame's barrier starts from a layout the image has left.
            engineImageBarrier(
                cmd,
                image: image.image,
                srcLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                srcAccess: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue),
                srcStage: VK_PIPELINE_STAGE_TRANSFER_BIT,
                dstLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
                dstStage: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
            )
        }

        // The copy hands back each texel's components in R, G, B, A byte
        // order — not the image format's own byte order, which for a BGRA
        // canvas would put B first. `RasterImage` is premultiplied ARGB
        // words, so the two are a swap of R and B apart.
        //
        // Measured, not assumed, and the measurement is in the demo: the
        // Textures screen reads a texture back and compares it against
        // `renderImage` of the same tree, which is the CPU path and is
        // covered pixel by pixel in `RenderImageTests`. Reinterpreting the
        // words straight through — on the reasoning that a BGRA target's
        // bytes already *are* an ARGB word — came out with every colour's
        // red and blue exchanged while the same texture composited into the
        // window correctly, which is what says the swap belongs here and not
        // in the canvas.
        let words = host.mapped.bindMemory(to: UInt32.self, capacity: width * height)
        var pixels = [UInt32](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let rgba = words[index]
            let r = (rgba >> 0) & 0xFF
            let g = (rgba >> 8) & 0xFF
            let b = (rgba >> 16) & 0xFF
            let a = (rgba >> 24) & 0xFF
            pixels[index] = (a << 24) | (r << 16) | (g << 8) | b
        }
        return RasterImage(width: width, height: height, pixels: pixels)
    }

    /// A host-visible, coherent, mapped buffer of `byteCount` bytes, usable as
    /// a copy destination. The caller unmaps and frees it.
    private func makeHostBuffer(
        byteCount: Int
    ) -> (buffer: VkBuffer, memory: VkDeviceMemory, mapped: UnsafeMutableRawPointer)? {
        var info = VkBufferCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        info.size = VkDeviceSize(byteCount)
        info.usage = VkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue)
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var buffer: VkBuffer?
        guard vkCreateBuffer(engine.device, &info, nil, &buffer) == VK_SUCCESS, let buffer else {
            return nil
        }

        var requirements = VkMemoryRequirements()
        vkGetBufferMemoryRequirements(engine.device, buffer, &requirements)

        var allocation = VkMemoryAllocateInfo()
        allocation.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        allocation.allocationSize = requirements.size
        allocation.memoryTypeIndex = engine.findMemoryType(
            typeFilter: requirements.memoryTypeBits,
            properties: VkMemoryPropertyFlags(
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue
            )
        )

        var memory: VkDeviceMemory?
        guard vkAllocateMemory(engine.device, &allocation, nil, &memory) == VK_SUCCESS, let memory else {
            vkDestroyBuffer(engine.device, buffer, nil)
            return nil
        }
        vkBindBufferMemory(engine.device, buffer, memory, 0)

        var mapped: UnsafeMutableRawPointer?
        guard vkMapMemory(engine.device, memory, 0, VkDeviceSize(byteCount), 0, &mapped) == VK_SUCCESS,
              let mapped
        else {
            vkFreeMemory(engine.device, memory, nil)
            vkDestroyBuffer(engine.device, buffer, nil)
            return nil
        }
        return (buffer, memory, mapped)
    }
}
