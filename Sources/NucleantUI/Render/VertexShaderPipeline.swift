//
//  VertexShaderPipeline.swift
//  NucleantUI
//
//  The GPU half of a vertex + fragment module's slot: a colour-attachment
//  image the pipeline draws into, the graphics pipeline itself, and the
//  uniform and input buffers — the same descriptor set as `ShaderPipeline`
//  minus what a compute stage needs and a render pass in its place:
//    binding 1 — uniform buffer (`ShaderUniforms`), both stages
//    binding 2 — sampled image (the view's own pixels), for a `.shader` effect
//    binding 3 — storage buffer (the module's input), both stages, when any
//  Binding 0 (the storage image) does not exist here: the output is the
//  attachment. Binding 2 is the same `uContent` a compute effect samples, so
//  `.shader(_:)` over a vertex + fragment pair reads the view with the same
//  `layer(uv)` — the difference being that the shader draws its own geometry
//  over it, rather than one invocation per pixel. Same one-set pool per
//  shader, for the MoltenVK reason `ShaderPipeline` gives.
//

import CVulkan
import VulkanCore
import NucleantVulkan
import NucleantShader

/// Everything Vulkan behind one vertex + fragment module's slot.
@MainActor
final class VertexShaderPipeline {

    private let device: VkDevice

    private(set) var pipeline: VkPipeline?
    private(set) var pipelineLayout: VkPipelineLayout?
    private(set) var descriptorSet: VkDescriptorSet?

    private var setLayout: VkDescriptorSetLayout?
    private var descriptorPool: VkDescriptorPool?
    private var uniforms: BufferAndMemory
    /// The input's storage buffer, when it packs anything.
    private var arguments: BufferAndMemory?
    /// Floats the argument buffer can hold; 0 when there is none.
    let argumentCapacity: Int
    /// How both stages sample the inputs — one sampler for all of them.
    private var sampler: VkSampler?
    /// The sampled images, at the bindings the shader was compiled against —
    /// read by `createSetLayout`.
    private var inputs: [ShaderImageInput]

    /// `inputs` are the images the shader samples: the canvas a `.shader(_:)`
    /// effect drew its view into at binding 2, and a named texture at each
    /// binding from 4 up. Empty for a generative `Shader`.
    init<N: RenderContainerNode>(
        engine: VulkanRenderEngine<N>,
        renderPass: VkRenderPass,
        inputs: [ShaderImageInput] = [],
        spirv words: [UInt32],
        vertexEntryPoint: String,
        fragmentEntryPoint: String,
        argumentCapacity: Int = 0
    ) throws {
        self.device = engine.device
        self.argumentCapacity = argumentCapacity
        self.inputs = inputs
        self.uniforms = engine.createBuffer(
            size: MemoryLayout<ShaderUniforms>.stride,
            usage: VkBufferUsageFlags(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue)
        )
        if argumentCapacity > 0 {
            arguments = engine.createBuffer(
                size: argumentCapacity * MemoryLayout<Float>.stride,
                usage: VkBufferUsageFlags(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT.rawValue)
            )
        }

        let vertex = (spirv: words, entryPoint: vertexEntryPoint)
        let fragment = (spirv: words, entryPoint: fragmentEntryPoint)

        do {
            try createSetLayout()
            try createPipelineLayout()
            if !inputs.isEmpty { try createSampler() }
            pipeline = try InstancedQuadPipeline.create(
                device: device,
                renderPass: renderPass,
                layout: pipelineLayout!,
                vertex: vertex,
                fragment: fragment
            )
            try createDescriptorSet()
        } catch {
            destroy()
            throw error
        }
    }

    /// Per-frame uniform write — host-coherent, read by the next draw.
    func update(_ values: ShaderUniforms) {
        var copy = values
        uniforms.update(device: device, data: &copy, bytes: MemoryLayout<ShaderUniforms>.stride)
    }

    /// The input's packed bytes, whole. Bytes past the capacity are a
    /// caller error — the registry rebuilds the slot before it gets here.
    func updateArguments(bytes: [UInt8]) {
        guard let arguments, !bytes.isEmpty else { return }
        let count = min(bytes.count, argumentCapacity * MemoryLayout<Float>.stride)
        bytes.withUnsafeBytes { buffer in
            arguments.update(device: device, data: buffer.baseAddress!, bytes: count)
        }
    }

    /// Point the sampled-image descriptors at new handles — see
    /// `ShaderPipeline.rebindDescriptors`, which this mirrors for the
    /// graphics path.
    func rebindDescriptors(_ inputs: [ShaderImageInput]) {
        guard inputs.map(\.binding) == self.inputs.map(\.binding) else {
            nucleantLogError(
                "NucleantUI: vertex shader rebind ignored — \(inputs.count) inputs at "
                + "\(inputs.map(\.binding)) against a set built for \(self.inputs.map(\.binding))\n"
            )
            return
        }
        self.inputs = inputs
        writeInputs(inputs)
    }

    /// Idempotent. The caller drains the GPU first.
    func destroy() {
        if let sampler { vkDestroySampler(device, sampler, nil) }
        if let pipeline { vkDestroyPipeline(device, pipeline, nil) }
        if let pipelineLayout { vkDestroyPipelineLayout(device, pipelineLayout, nil) }
        if let setLayout { vkDestroyDescriptorSetLayout(device, setLayout, nil) }
        if let descriptorPool { vkDestroyDescriptorPool(device, descriptorPool, nil) }
        uniforms.destroy(device: device)
        arguments?.destroy(device: device)
        arguments = nil
        sampler = nil
        pipeline = nil
        pipelineLayout = nil
        setLayout = nil
        descriptorPool = nil
        descriptorSet = nil
        inputs = []
        uniforms = BufferAndMemory()
    }

    // MARK: - Creation

    private static let bothStages = VkShaderStageFlags(
        VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue
    )

    private func createSetLayout() throws {
        var uniform = VkDescriptorSetLayoutBinding()
        uniform.binding = 1
        uniform.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        uniform.descriptorCount = 1
        uniform.stageFlags = Self.bothStages

        var bindings = [uniform]
        for sampled in inputs {
            var input = VkDescriptorSetLayoutBinding()
            input.binding = UInt32(sampled.binding)
            input.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
            input.descriptorCount = 1
            // Both stages: the fragment reads it through `layer()`, and a
            // vertex + fragment module is one module, so the vertex entry
            // point shares the global even when it never samples it.
            input.stageFlags = Self.bothStages
            bindings.append(input)
        }
        if arguments != nil {
            var storage = VkDescriptorSetLayoutBinding()
            storage.binding = 3
            storage.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
            storage.descriptorCount = 1
            storage.stageFlags = Self.bothStages
            bindings.append(storage)
        }
        let result = bindings.withUnsafeBufferPointer { buffer -> VkResult in
            var info = VkDescriptorSetLayoutCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
            info.bindingCount = UInt32(buffer.count)
            info.pBindings = buffer.baseAddress
            return vkCreateDescriptorSetLayout(device, &info, nil, &setLayout)
        }
        guard result == VK_SUCCESS else { throw ShaderError.vulkan("descriptor set layout") }
    }

    private func createPipelineLayout() throws {
        let result = withUnsafePointer(to: setLayout) { layoutPtr -> VkResult in
            var info = VkPipelineLayoutCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
            info.setLayoutCount = 1
            info.pSetLayouts = layoutPtr
            return vkCreatePipelineLayout(device, &info, nil, &pipelineLayout)
        }
        guard result == VK_SUCCESS else { throw ShaderError.vulkan("pipeline layout") }
    }

    /// Linear, clamped, as `ShaderPipeline`'s: a distortion that samples past
    /// the edge gets the edge pixel rather than a wrapped copy of the far side.
    private func createSampler() throws {
        var info = VkSamplerCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        info.magFilter = VK_FILTER_LINEAR
        info.minFilter = VK_FILTER_LINEAR
        info.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        info.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        info.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        guard vkCreateSampler(device, &info, nil, &sampler) == VK_SUCCESS else {
            throw ShaderError.vulkan("sampler")
        }
    }

    private func createDescriptorSet() throws {
        var sizes = [
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1),
        ]
        if !inputs.isEmpty {
            sizes.append(VkDescriptorPoolSize(
                type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: UInt32(inputs.count)
            ))
        }
        if arguments != nil {
            sizes.append(VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, descriptorCount: 1))
        }
        let poolResult = sizes.withUnsafeBufferPointer { buffer -> VkResult in
            var info = VkDescriptorPoolCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
            info.maxSets = 1
            info.poolSizeCount = UInt32(buffer.count)
            info.pPoolSizes = buffer.baseAddress
            return vkCreateDescriptorPool(device, &info, nil, &descriptorPool)
        }
        guard poolResult == VK_SUCCESS else { throw ShaderError.vulkan("descriptor pool") }

        let allocResult = withUnsafePointer(to: setLayout) { layoutPtr -> VkResult in
            var info = VkDescriptorSetAllocateInfo()
            info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            info.descriptorPool = descriptorPool
            info.descriptorSetCount = 1
            info.pSetLayouts = layoutPtr
            return vkAllocateDescriptorSets(device, &info, &descriptorSet)
        }
        guard allocResult == VK_SUCCESS else { throw ShaderError.vulkan("descriptor set") }

        var bufferInfo = VkDescriptorBufferInfo()
        bufferInfo.buffer = uniforms.buffer
        bufferInfo.offset = 0
        bufferInfo.range = VkDeviceSize(MemoryLayout<ShaderUniforms>.stride)

        var argumentInfo = VkDescriptorBufferInfo()
        argumentInfo.buffer = arguments?.buffer
        argumentInfo.offset = 0
        argumentInfo.range = VkDeviceSize(VK_WHOLE_SIZE)

        withUnsafePointer(to: &bufferInfo) { bufferPtr in
            withUnsafePointer(to: &argumentInfo) { argumentPtr in
                var writeUniform = VkWriteDescriptorSet()
                writeUniform.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                writeUniform.dstSet = descriptorSet
                writeUniform.dstBinding = 1
                writeUniform.descriptorCount = 1
                writeUniform.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
                writeUniform.pBufferInfo = bufferPtr

                var writes = [writeUniform]
                if arguments != nil {
                    var writeArguments = VkWriteDescriptorSet()
                    writeArguments.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                    writeArguments.dstSet = descriptorSet
                    writeArguments.dstBinding = 3
                    writeArguments.descriptorCount = 1
                    writeArguments.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
                    writeArguments.pBufferInfo = argumentPtr
                    writes.append(writeArguments)
                }
                vkUpdateDescriptorSets(device, UInt32(writes.count), &writes, 0, nil)
            }
        }
        writeInputs(inputs)
    }

    /// Write every sampled-image descriptor with `inputs`' current handles —
    /// the graphics twin of `ShaderPipeline.writeInputs`.
    private func writeInputs(_ inputs: [ShaderImageInput]) {
        guard !inputs.isEmpty, let descriptorSet, let sampler else { return }
        var infos = inputs.map { input -> VkDescriptorImageInfo in
            var info = VkDescriptorImageInfo()
            info.sampler = sampler
            info.imageView = input.imageView
            info.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
            return info
        }
        infos.withUnsafeMutableBufferPointer { buffer in
            var writes = inputs.enumerated().map { index, input -> VkWriteDescriptorSet in
                var write = VkWriteDescriptorSet()
                write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                write.dstSet = descriptorSet
                write.dstBinding = UInt32(input.binding)
                write.descriptorCount = 1
                write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
                write.pImageInfo = UnsafePointer(buffer.baseAddress! + index)
                return write
            }
            vkUpdateDescriptorSets(device, UInt32(writes.count), &writes, 0, nil)
        }
    }
}
