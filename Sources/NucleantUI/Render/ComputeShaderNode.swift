//
//  ComputeShaderNode.swift
//  NucleantUI
//
//  This framework's own compute slot, and the container that borrows an
//  image somebody else owns.
//
//  `NucleantRenderNode.Context` is NucleantUI's enum and `VulkanRenderEngine`
//  is generic over its container node precisely so each host picks its own set
//  of backends. So the node a `Shader` view, a `.shader(_:)` effect and a
//  `RenderTexture` dispatch through is ours, written against
//  `NucleantVulkan.VulkanRenderNode` — all the protocol asks for is the image,
//  the compute trio, `dirty`, an `update` and a teardown.
//
//  Two things follow from owning it. A dispatch's result is released to
//  *both* the compute and the fragment stage, so an image one shader wrote can
//  be sampled by another shader in the same frame — not only by the composite
//  pass. And a shader reads as many sampled images as it was built with
//  (binding 2 is the content, 4 and up are named textures), rather than the
//  single input the slot has had so far.
//

import Observation
import CVulkan
import VulkanCore
import NucleantVulkan

/// One image a shader samples, at the binding it was compiled against.
///
/// Borrowed, always: whoever created the image — a canvas node, another
/// slot, a `RenderTexture` — owns it and frees it. This carries only the
/// handle the descriptor set is written with, plus the name the shader knows
/// it by, which is what makes a rebind traceable when several are bound.
public struct ShaderImageInput: @unchecked Sendable {

    /// What the shader body calls it. `uContent` for the view's own pixels —
    /// the `layer(uv)` texture — and the author's own name for anything else.
    public let name: String
    public let imageView: VkImageView
    /// Descriptor binding, fixed at compile time: 2 for the content, 4 and up
    /// for named textures (0 output, 1 uniforms, 3 arguments).
    public let binding: Int

    public init(name: String, imageView: VkImageView, binding: Int) {
        self.name = name
        self.imageView = imageView
        self.binding = binding
    }

    /// The view a `.shader(_:)` effect is applied to, as `layer(uv)` reads it.
    public static func content(_ imageView: VkImageView) -> ShaderImageInput {
        ShaderImageInput(name: "uContent", imageView: imageView, binding: 2)
    }

    /// A named texture, the `index`th of them, at binding 4 and up.
    public static func texture(_ name: String, _ imageView: VkImageView, at index: Int) -> ShaderImageInput {
        ShaderImageInput(name: name, imageView: imageView, binding: 4 + index)
    }
}

/// A compute-written image: the slot behind every `Shader` view, every
/// `.shader(_:)` effect, and every shader-written `RenderTexture`.
///
/// It owns its image/view/memory and carries the pipeline handles
/// `ShaderPipeline` installs. With no pipeline installed it has no content, so
/// it stays out of `engine.readable` rather than compositing whatever the
/// allocation happened to contain.
@Observable
public final class ComputeShaderNode: VulkanRenderNode, @unchecked Sendable {

    public typealias ContainerNode = NucleantRenderNode
    public typealias Engine = NucleantRenderEngine

    public var width: UInt32
    public var height: UInt32

    public var image: VkImage
    public var imageView: VkImageView
    /// The allocation backing `image`, carried for whoever tears the node
    /// down — the same contract as the engine's own nodes.
    public var memory: VkDeviceMemory?

    public var computePipeline: VkPipeline?
    public var computeLayout: VkPipelineLayout?
    public var computeDescriptorSet: VkDescriptorSet?
    public var dirty: Bool = true

    /// A compute slot's image always carries STORAGE usage — it is what the
    /// dispatch binds as its output.
    public let storageCapable: Bool = true

    /// The images this node's shader samples, in binding order.
    ///
    /// The descriptor set snapshots the `VkImageView` it was written with, so
    /// changing one here is not enough on its own — set `descriptorsNeedRebind`
    /// with it. `ShaderSlotRegistry` is the one that knows an input changed
    /// (it is the one that rebuilt the texture), so it writes both and consumes
    /// the flag; no Observation round-trip is involved.
    public var inputs: [ShaderImageInput]

    /// Set when `inputs` changed after the descriptor set was written. Whoever
    /// owns the pipeline consumes it: rewrite the set behind a drain, then
    /// clear it.
    public var descriptorsNeedRebind: Bool = false

    /// The image's actual Vulkan-tracked layout, so the pre-dispatch barrier
    /// starts from where the last frame left it instead of a stale guess.
    private var currentLayout: VkImageLayout

    public init(
        width: UInt32,
        height: UInt32,
        image: VkImage,
        imageView: VkImageView,
        memory: VkDeviceMemory? = nil,
        inputs: [ShaderImageInput] = []
    ) {
        self.width = width
        self.height = height
        self.image = image
        self.imageView = imageView
        self.memory = memory
        self.inputs = inputs
        // Its creator transitions a fresh storage image UNDEFINED → GENERAL
        // once, so the first dispatch has somewhere valid to write.
        self.currentLayout = VK_IMAGE_LAYOUT_GENERAL
    }

    /// No canvas draw — the dispatch writes every pixel of the image.
    public func update(_ engine: Engine, slot: NucleantRenderNode, cmd: VkCommandBuffer) {
        guard slot.needsRender else { return }
        guard let pipeline = computePipeline,
              let layout = computeLayout,
              let descriptorSet = computeDescriptorSet
        else { return }

        let shaderAccess = VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue)
            | VkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT.rawValue)
        let compute = VkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT.rawValue)

        barrier(
            cmd,
            srcLayout: currentLayout,
            srcAccess: shaderAccess,
            srcStage: compute,
            dstLayout: VK_IMAGE_LAYOUT_GENERAL,
            dstAccess: shaderAccess,
            dstStage: compute
        )

        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline)
        var set: VkDescriptorSet? = descriptorSet
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, nil)
        // 8×8 groups, matching the `local_size` both the GLSL wrapper and
        // PyShader's compute interface declare.
        vkCmdDispatch(cmd, (width + 7) / 8, (height + 7) / 8, 1)

        // Released to the fragment stage *and* the compute stage: the
        // composite pass samples it in a fragment shader, but another shader
        // in the same frame may sample it too — a `RenderTexture` mixed into
        // a second shader, a texture written by one effect and read by the
        // next. Naming only the fragment stage left that second read
        // unsynchronised.
        barrier(
            cmd,
            srcLayout: VK_IMAGE_LAYOUT_GENERAL,
            srcAccess: VkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT.rawValue),
            srcStage: compute,
            dstLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
            dstStage: compute | VkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue)
        )
        currentLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        engine.readable.insert(slot.id)
        // `slot.needsRender` is cleared by the container after this returns,
        // the same steady state as every other node kind.
    }

    /// Free the image/view/memory this node owns. `inputs` are borrowed, so
    /// they are left for their owners.
    public func destroyResources(_ engine: Engine) {
        vkDeviceWaitIdle(engine.device)
        vkDestroyImageView(engine.device, imageView, nil)
        vkDestroyImage(engine.device, image, nil)
        if let memory {
            vkFreeMemory(engine.device, memory, nil)
        }
    }

    private func barrier(
        _ cmd: VkCommandBuffer,
        srcLayout: VkImageLayout,
        srcAccess: VkAccessFlags,
        srcStage: VkPipelineStageFlags,
        dstLayout: VkImageLayout,
        dstAccess: VkAccessFlags,
        dstStage: VkPipelineStageFlags
    ) {
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        barrier.srcAccessMask = srcAccess
        barrier.dstAccessMask = dstAccess
        barrier.oldLayout = srcLayout
        barrier.newLayout = dstLayout
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image
        barrier.subresourceRange = VkImageSubresourceRange(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            baseMipLevel: 0, levelCount: 1,
            baseArrayLayer: 0, layerCount: 1
        )
        vkCmdPipelineBarrier(cmd, srcStage, dstStage, 0, 0, nil, 0, nil, 1, &barrier)
    }
}

/// A container for an image this node does not own: one *placement* of a
/// `RenderTexture`.
///
/// A texture may be shown in several places at once and sampled by a shader
/// at the same time, all of it one image. So the image's owner is the
/// `RenderTexture` — which frees it once, through the registry's deferred
/// release — and each placement gets one of these, pointing at the texture's
/// current handles. `update` therefore does nothing but publish: there is no
/// dispatch and no canvas draw to run, and without the publish the composite
/// pass skips the slot entirely (`recordComposite` gates on `readable`).
@Observable
public final class RenderTextureNode: VulkanRenderNode, @unchecked Sendable {

    public typealias ContainerNode = NucleantRenderNode
    public typealias Engine = NucleantRenderEngine

    public var width: UInt32
    public var height: UInt32

    public var image: VkImage
    public var imageView: VkImageView

    /// The texture has been rendered at least once, so the image holds
    /// pixels rather than an untouched allocation.
    public var hasContent: Bool

    public var computePipeline: VkPipeline?
    public var computeLayout: VkPipelineLayout?
    public var computeDescriptorSet: VkDescriptorSet?
    public var dirty: Bool = true

    /// Whatever the texture's backing is — a canvas node's colour attachment,
    /// a compute slot's storage image — a placement never writes it.
    public let storageCapable: Bool = false

    public init(
        width: UInt32,
        height: UInt32,
        image: VkImage,
        imageView: VkImageView,
        hasContent: Bool = false
    ) {
        self.width = width
        self.height = height
        self.image = image
        self.imageView = imageView
        self.hasContent = hasContent
    }

    /// Point this placement at the texture's current image. The engine caches
    /// its composite descriptor set per slot id, so the owner invalidates that
    /// (`engine.invalidateComposite(id:)`) for the new handle to be sampled.
    public func rebind(image: VkImage, imageView: VkImageView, width: UInt32, height: UInt32) {
        self.image = image
        self.imageView = imageView
        self.width = width
        self.height = height
        dirty = true
    }

    /// Publish only. The image was left in `SHADER_READ_ONLY_OPTIMAL` by
    /// whoever wrote it — the texture's canvas node, or a compute slot — and
    /// that is the layout the composite samples in, so there is nothing to
    /// transition here either.
    public func update(_ engine: Engine, slot: NucleantRenderNode, cmd: VkCommandBuffer) {
        guard hasContent else { return }
        engine.readable.insert(slot.id)
    }

    /// Nothing: the image belongs to the `RenderTexture`, which frees it once
    /// however many placements borrowed it.
    public func destroyResources(_ engine: Engine) {}
}
