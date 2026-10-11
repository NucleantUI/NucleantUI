//
//  ShaderPipeline.swift
//  NucleantUI
//
//  The GPU half of a `Shader` view: a storage image the compute shader writes,
//  the compute pipeline itself, and a uniform buffer carrying time/resolution/
//  mouse. `ComputeShaderNode` knows how to dispatch a compute pipeline into
//  its own image and barrier the result for whoever reads it next — it simply
//  has no factory, so this is that factory.
//
//  Descriptor layout:
//    binding 0 — storage image (the shader's output)
//    binding 1 — uniform buffer (`ShaderUniforms`)
//    binding 2 — sampled image (the view's own pixels), for a `.shader` effect
//    binding 3 — storage buffer (`ShaderArgument`s), when the shader has any
//    binding 4+ — one sampled image per named texture the shader declares
//  A dedicated one-set pool per shader, for the reason the engine gives every
//  composite node its own: MoltenVK packing several same-layout sets into one
//  pool misaligns Metal argument-buffer offsets.
//

import CVulkan
import VulkanCore
import NucleantVulkan
import NucleantShader
import PyShader

/// What every shader gets for free, matching the `Uniforms` block the wrapper
/// in `ShaderSource` declares. `std140` puts a `vec2` on an 8-byte boundary,
/// which the explicit padding here honours.
struct ShaderUniforms {
    // vec4 timeInfo — x: seconds, y: frame delta, z: frame number
    var time: Float = 0
    var timeDelta: Float = 0
    var frame: Float = 0
    var _pad0: Float = 0
    // vec4 resolution — xy only
    var resolutionX: Float = 0
    var resolutionY: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
    // vec4 mouse — xy: position, zw: position while pressed (ShaderToy's shape)
    var mouseX: Float = 0
    var mouseY: Float = 0
    var mouseClickX: Float = 0
    var mouseClickY: Float = 0
}

enum ShaderError: Error {
    case compileFailed(String)
    case vulkan(String)
}

/// What a `ShaderFunction` becomes on its way to `vkCreateShaderModule`:
/// GLSL still to be compiled by shaderc, or SPIR-V already produced by
/// PyShader. Both target the descriptor layout described at the top of this
/// file, so the pipeline is the same from here on.
enum ShaderCode {
    case glsl(String)
    case spirv([UInt32])

    /// The code for a function under the compute contract. `samplesContent`
    /// adds the view's own pixels at binding 2 (`layer(uv)`); `arguments`
    /// declares the `ShaderArgument`s at binding 3; `textures` declares one
    /// named sampler per `RenderTexture` at binding 4 and up.
    /// `contentIsTopDown` — the pixels are a canvas node's own image, stored
    /// top-down rather than drawn y-up as a layer is — has `layer(uv)` read
    /// them upright.
    static func compute(
        _ function: ShaderFunction,
        samplesContent: Bool,
        contentIsTopDown: Bool = false,
        arguments: ShaderArguments,
        textures: ShaderTextures = .none
    ) throws -> ShaderCode {
        switch function.language {
        case .glsl:
            return .glsl(ShaderSource.compute(
                functions: function.functions,
                body: function.body,
                samplesContent: samplesContent,
                arguments: arguments,
                textures: textures
            ))
        case .pyshader:
            let interface = ComputeImageInterface.nucleantUI(
                samplesContent: samplesContent,
                contentIsTopDown: contentIsTopDown,
                arguments: try ShaderArgumentKind.kinds(of: arguments),
                textures: textures.declarations
            )
            do {
                return .spirv(try PyShader.compile(function.body, target: .computeImage(interface)).spirv)
            } catch let error as PyShaderError {
                // Python line numbers, since that is what was written.
                throw ShaderError.compileFailed("PyShader: \(error)")
            }
        case .spirv:
            // Already compiled, and compiled against this same layout — see
            // `ShaderFunction.init(spirv:)`. `samplesContent`, `arguments`
            // and `textures` described what to *generate*, and there is
            // nothing to generate: the module declares what it reads, and
            // the bindings it declares are the ones below.
            return .spirv(function.spirv)
        }
    }
}

extension ShaderArgumentKind {
    /// From the GLSL declaration `ShaderArgument` produces for itself.
    init?(glslType: String) {
        switch glslType {
        case "float": self = .float
        case "vec2": self = .float2
        case "vec3": self = .float3
        case "vec4": self = .float4
        case "float[]": self = .floatArray
        case "vec2[]": self = .float2Array
        case "vec3[]": self = .float3Array
        case "vec4[]": self = .float4Array
        default: return nil
        }
    }

    /// PyShader's view of `arguments`, or the error for one it cannot take.
    static func kinds(of arguments: ShaderArguments) throws -> [(name: String, kind: ShaderArgumentKind)] {
        try arguments.declarations.map { declaration in
            guard let kind = ShaderArgumentKind(glslType: declaration.type) else {
                throw ShaderError.compileFailed(
                    "PyShader: argument '\(declaration.name)' is a \(declaration.type); "
                    + "PyShader takes float, float2/3/4, color and arrays of them"
                )
            }
            return (declaration.name, kind)
        }
    }
}

/// Wraps user GLSL into the compute contract above.
enum ShaderSource {

    /// A body written in fragment-shader terms — `uv`, `time`, `resolution`
    /// and `mouse` are in scope and it assigns `fragColor` — becomes a
    /// complete compute shader. Source that already starts with `#version` is
    /// passed through untouched, so a full compute shader is an escape hatch.
    ///
    /// With `samplesContent`, the wrapper also declares the view's own pixels
    /// as `uContent` (and ShaderToy's `iChannel0`), plus `layer(uv)` to read
    /// them — what a `.shader(_:)` effect is given. `textures` adds one named
    /// sampler per `RenderTexture`, read as `a(uv)` and measured as `a_size`,
    /// which is the interface PyShader compiles against — declared here too so
    /// the GLSL inlet does not quietly mean something else.
    ///
    /// Local size 8×8 matches the `(w + 7) / 8` dispatch in
    /// `ComputeShaderNode.update` exactly.
    static func compute(
        functions: String,
        body: String,
        samplesContent: Bool = false,
        arguments: ShaderArguments = .none,
        textures: ShaderTextures = .none
    ) -> String {
        if body.trimmingCharactersInWhitespace().hasPrefix("#version") {
            return body
        }
        let (argumentDeclarations, argumentLoads) = argumentSource(arguments)
        let textureDeclarations = textureSource(textures)
        let content = samplesContent ? """
        // The view this effect is applied to, rendered into its own texture
        // and stored y-up like everything else in shader space — so
        // `layer(uv)` is the view's pixel under the current one, and an
        // unmodified ShaderToy `texture(iChannel0, uv)` reads it upright.
        layout(binding = 2) uniform sampler2D uContent;
        #define iChannel0 uContent
        vec3 iChannelResolution[4];

        vec4 layer(vec2 p) { return texture(uContent, p); }
        """ : ""
        return """
        #version 450

        layout(local_size_x = 8, local_size_y = 8) in;
        layout(binding = 0, rgba8) uniform writeonly image2D uOutput;
        layout(binding = 1) uniform Uniforms {
            vec4 timeInfo;    // x: time, y: delta, z: frame
            vec4 res;         // xy: resolution
            vec4 mouseInfo;   // xy: position, zw: position while pressed
        } u;
        \(content)
        \(textureDeclarations)
        \(argumentDeclarations)

        // Constants every ShaderToy-style body reaches for, so each one does
        // not have to redeclare them.
        const float PI      = 3.14159265359;
        const float TAU     = 6.28318530718;
        const float HALF_PI = 1.57079632679;

        // File-scope, not locals in `main`: a helper in `functions` has to be
        // able to read them, and ported shaders routinely do — CyberFuji's
        // `sun()` and `grid()` both use `time` without taking it as a
        // parameter. Assigned once at the top of `main`, which is the only
        // caller, so every helper sees the current frame's values.
        float time;
        vec2  resolution;
        vec2  mouse;

        // The ShaderToy uniform set, in ShaderToy's own types — `iResolution`
        // is a vec3 and `iMouse` a vec4 there, and shaders written against it
        // rely on that (`iMouse.z > 0.0` to test for a press, `iResolution.xy`
        // to divide by). Declaring them with the right shapes is most of what
        // makes an unmodified `mainImage` compile.
        float iTime;
        float iTimeDelta;
        int   iFrame;
        vec3  iResolution;
        vec4  iMouse;

        \(functions)

        void main() {
            ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
            ivec2 size  = imageSize(uOutput);
            if (pixel.x >= size.x || pixel.y >= size.y) { return; }

            time        = u.timeInfo.x;
            resolution  = vec2(size);
            // Pointer position is delivered top-down (the view system's
            // convention) and flipped here with everything else.
            mouse       = vec2(u.mouseInfo.x, resolution.y - u.mouseInfo.y);
            iTime       = time;
            iTimeDelta  = u.timeInfo.y;
            iFrame      = int(u.timeInfo.z);
            iResolution = vec3(resolution, 1.0);
            iMouse      = vec4(mouse, u.mouseInfo.z, resolution.y - u.mouseInfo.w);
        \(samplesContent ? "    iChannelResolution[0] = iResolution;" : "")
        \(argumentLoads)

            // Shader space is y-up, with (0, 0) at the bottom-left — the
            // convention every ShaderToy shader is written against. The image
            // itself is stored top-down, so only the coordinates handed to the
            // body are flipped; `pixel`, the store location, is untouched.
            //
            // Without this every ported shader came out vertically mirrored,
            // which is subtle in a symmetric one (Plasma) and obvious in a
            // shader with a horizon: CyberFuji's `if (p.y < -0.2)` draws its
            // neon floor grid, and it was appearing along the top.
            vec2 fragCoord = vec2(float(pixel.x) + 0.5, float(size.y - pixel.y) - 0.5);
            vec2 uv        = fragCoord / resolution;
            vec4 fragColor = vec4(0.0, 0.0, 0.0, 1.0);

            // The body is its own scope, so a port may redeclare `uv` or
            // `fragCoord` — many do — and shadow these rather than collide.
            {
        \(body)
            }

            imageStore(uOutput, pixel, fragColor);
        }
        """
    }
}

extension ShaderSource {
    /// The GLSL behind `ShaderArgument`s: one storage buffer of floats, a
    /// header of (offset, count) pairs at its front, and a named variable —
    /// or, for an array, an accessor function and a count — per argument.
    /// Values are loaded at the top of `main` so helpers in `functions` can
    /// read the scalars the way they read `time`.
    ///
    /// The declarations depend only on names and kinds, never on values or
    /// lengths, so changing an array's contents or length never recompiles.
    static func argumentSource(_ arguments: ShaderArguments) -> (declarations: String, loads: String) {
        guard !arguments.isEmpty else { return ("", "") }
        var declarations = """
        layout(std430, binding = 3) readonly buffer ShaderArgs { float data[]; } uArgs;
        #define ARG_OFFSET(i) int(uArgs.data[(i) * 2])
        #define ARG_COUNT(i)  int(uArgs.data[(i) * 2 + 1])

        """
        var loads = ""
        for (index, declaration) in arguments.declarations.enumerated() {
            let name = declaration.name
            let at = "ARG_OFFSET(\(index))"
            let type = declaration.type
            if type.hasSuffix("[]") {
                // `name(i)` reads element i — `width` floats from the
                // element's start — and `nameCount` is the length.
                let element = String(type.dropLast(2))
                let width = Self.componentCount(of: element)
                let load = Self.load(element, from: "at")
                declarations += """
                int \(name)Count;
                \(element) \(name)(int i) {
                    int n = ARG_COUNT(\(index));
                    int at = \(at) + clamp(i, 0, n - 1) * \(width);
                    return n > 0 ? \(load) : \(element)(0.0);
                }

                """
                loads += "    \(name)Count = ARG_COUNT(\(index));\n"
            } else {
                declarations += "\(type) \(name);\n"
                loads += "    \(name) = \(Self.load(type, from: at));\n"
            }
        }
        return (declarations, loads)
    }

    private static func componentCount(of type: String) -> Int {
        switch type {
        case "vec2": return 2
        case "vec3": return 3
        case "vec4": return 4
        default: return 1
        }
    }

    /// The expression that reads one `type` starting at float index `at`.
    private static func load(_ type: String, from at: String) -> String {
        let width = componentCount(of: type)
        let components = (0..<width).map { $0 == 0 ? "uArgs.data[\(at)]" : "uArgs.data[\(at) + \($0)]" }
        return width == 1 ? components[0] : "\(type)(\(components.joined(separator: ", ")))"
    }
}

extension ShaderSource {
    /// The GLSL behind named textures, matching what PyShader emits for the
    /// same `ShaderTexture`s: one `sampler2D` per texture at its own binding,
    /// a reader function of the texture's own name, and `<name>_size`.
    ///
    /// Nothing new is written in GLSL — this is here so a body ported between
    /// the two inlets reads the same in both. A `RenderTexture` is stored
    /// top-down, so the read flips y exactly as `isTopDown` does there.
    static func textureSource(_ textures: ShaderTextures) -> String {
        guard !textures.isEmpty else { return "" }
        var source = ""
        for declaration in textures.declarations {
            let name = declaration.name
            let sampler = "uTex_\(name)"
            let coordinate = declaration.isTopDown ? "vec2(p.x, 1.0 - p.y)" : "p"
            source += """
            layout(binding = \(declaration.binding)) uniform sampler2D \(sampler);
            vec4 \(name)(vec2 p) { return texture(\(sampler), \(coordinate)); }
            #define \(name)_size textureSize(\(sampler), 0)

            """
        }
        return source
    }
}

extension ShaderTextures {
    /// What PyShader declares for these textures. Every `RenderTexture` is
    /// stored top-down (a canvas image's own orientation), so every one of
    /// them reads flipped — `contentIsTopDown`'s rule, per texture.
    /// `ShaderTexture` unqualified: `PyShader` is the module *and* an enum in
    /// it, so `PyShader.ShaderTexture` looks inside the enum.
    var declarations: [ShaderTexture] {
        inputs.enumerated().map { index, input in
            ShaderTexture(name: input.name, binding: 4 + index, isTopDown: true)
        }
    }
}

private extension String {
    func trimmingCharactersInWhitespace() -> String {
        var result = Substring(self)
        while let first = result.first, first.isWhitespace || first.isNewline {
            result = result.dropFirst()
        }
        return String(result)
    }
}

/// Everything Vulkan behind one `Shader` view.
@MainActor
final class ShaderPipeline {

    private let device: VkDevice

    private(set) var pipeline: VkPipeline?
    private(set) var pipelineLayout: VkPipelineLayout?
    private(set) var descriptorSet: VkDescriptorSet?

    private var setLayout: VkDescriptorSetLayout?
    private var shaderModule: VkShaderModule?
    private var descriptorPool: VkDescriptorPool?
    private var uniforms: BufferAndMemory
    /// How the shader samples its inputs — one sampler for all of them,
    /// since they are all read the same way. `nil` when it has none.
    private var sampler: VkSampler?
    /// The sampled images, at the bindings the shader was compiled against.
    /// Kept so a rebind can be checked against what the set layout holds.
    private var inputs: [ShaderImageInput]
    /// The `ShaderArgument` storage buffer, when the shader declares any.
    /// Sized once, with headroom; a list that outgrows it rebuilds the slot.
    private var arguments: BufferAndMemory?
    /// Floats the argument buffer can hold; 0 when there is none.
    let argumentCapacity: Int

    /// `inputs` are the images the shader samples: the canvas a `.shader`
    /// effect's view is drawn into at binding 2, and a named texture at each
    /// binding from 4 up. Each is left in `SHADER_READ_ONLY_OPTIMAL` by
    /// whoever wrote it, whose update runs before this pipeline's dispatch.
    ///
    /// `argumentCapacity` is how many floats of `ShaderArgument` data to make
    /// room for — 0 for a shader without arguments, which then has no
    /// binding 3 at all.
    init(
        engine: NucleantRenderEngine,
        imageView: VkImageView,
        inputs: [ShaderImageInput] = [],
        source: ShaderCode,
        argumentCapacity: Int = 0
    ) throws {
        self.device = engine.device
        self.inputs = inputs
        self.argumentCapacity = argumentCapacity
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

        let spirv: [UInt32]
        switch source {
        case .spirv(let words):
            spirv = words
        case .glsl(let glsl):
            guard let compiled = VKShaderCompiler.shared.tryCompileCompute(glsl) else {
                uniforms.destroy(device: device)
                arguments?.destroy(device: device)
                // The real GLSL diagnostics, with the line numbers of the *wrapped*
                // shader — which is what someone pasting a ShaderToy source needs
                // to see rather than a bare "failed".
                throw ShaderError.compileFailed(
                    VKShaderCompiler.shared.lastErrorMessage ?? "shaderc rejected the compute shader"
                )
            }
            spirv = compiled
        }

        do {
            try createSetLayout()
            try createPipelineLayout()
            shaderModule = try ShaderModuleLoader.load(device: device, spirv: spirv)
            try createPipeline()
            if !inputs.isEmpty { try createSampler() }
            try createDescriptorSet(imageView: imageView)
        } catch {
            destroy()
            throw error
        }
    }

    /// Per-frame uniform write. Host-visible and coherent, so this is a plain
    /// memcpy with no barrier — the value the next dispatch reads.
    func update(_ values: ShaderUniforms) {
        var copy = values
        uniforms.update(
            device: device,
            data: &copy,
            bytes: MemoryLayout<ShaderUniforms>.stride
        )
    }

    /// The argument buffer, whole. Same contract as `update`: host-coherent,
    /// read by the next dispatch. A list longer than the capacity is a
    /// caller error — the registry rebuilds the slot before it gets here.
    func updateArguments(_ packed: [Float]) {
        guard let arguments, !packed.isEmpty else { return }
        let count = min(packed.count, argumentCapacity)
        packed.withUnsafeBufferPointer { buffer in
            arguments.update(
                device: device,
                data: UnsafeRawPointer(buffer.baseAddress!),
                bytes: count * MemoryLayout<Float>.stride
            )
        }
    }

    /// Point the sampled-image descriptors at new handles, for inputs whose
    /// *image* changed but whose names, order and bindings did not — a
    /// `RenderTexture` that was resized, a layer canvas retargeted.
    ///
    /// A descriptor set snapshots the `VkImageView` it was written with, so
    /// without this the shader keeps sampling the old image however often it
    /// is dispatched. The caller drains the device first: the set may still be
    /// bound in a command buffer in flight. A set whose *shape* changed is not
    /// this — the shader was compiled against those bindings, so the slot is
    /// rebuilt instead.
    func rebindDescriptors(_ inputs: [ShaderImageInput]) {
        guard inputs.map(\.binding) == self.inputs.map(\.binding) else {
            nucleantLogError(
                "NucleantUI: shader rebind ignored — \(inputs.count) inputs at "
                + "\(inputs.map(\.binding)) against a set built for \(self.inputs.map(\.binding))\n"
            )
            return
        }
        self.inputs = inputs
        writeInputs(inputs)
    }

    /// Idempotent. The caller drains the GPU first — an in-flight command
    /// buffer may still reference these objects.
    func destroy() {
        if let pipeline { vkDestroyPipeline(device, pipeline, nil) }
        if let pipelineLayout { vkDestroyPipelineLayout(device, pipelineLayout, nil) }
        if let shaderModule { vkDestroyShaderModule(device, shaderModule, nil) }
        if let setLayout { vkDestroyDescriptorSetLayout(device, setLayout, nil) }
        if let descriptorPool { vkDestroyDescriptorPool(device, descriptorPool, nil) }
        if let sampler { vkDestroySampler(device, sampler, nil) }
        uniforms.destroy(device: device)
        arguments?.destroy(device: device)
        arguments = nil
        pipeline = nil
        pipelineLayout = nil
        shaderModule = nil
        setLayout = nil
        descriptorPool = nil
        descriptorSet = nil
        sampler = nil
        inputs = []
        uniforms = BufferAndMemory()
    }

    // MARK: - Creation

    private func createSetLayout() throws {
        var output = VkDescriptorSetLayoutBinding()
        output.binding = 0
        output.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
        output.descriptorCount = 1
        output.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT.rawValue)

        var uniform = VkDescriptorSetLayoutBinding()
        uniform.binding = 1
        uniform.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        uniform.descriptorCount = 1
        uniform.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT.rawValue)

        var bindings = [output, uniform]
        for sampled in inputs {
            var input = VkDescriptorSetLayoutBinding()
            input.binding = UInt32(sampled.binding)
            input.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
            input.descriptorCount = 1
            input.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT.rawValue)
            bindings.append(input)
        }
        if arguments != nil {
            var storage = VkDescriptorSetLayoutBinding()
            storage.binding = 3
            storage.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
            storage.descriptorCount = 1
            storage.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT.rawValue)
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

    private func createPipeline() throws {
        let result = "main".withCString { entry -> VkResult in
            var stage = VkPipelineShaderStageCreateInfo()
            stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
            stage.stage = VK_SHADER_STAGE_COMPUTE_BIT
            stage.module = shaderModule
            stage.pName = entry

            var info = VkComputePipelineCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO
            info.stage = stage
            info.layout = pipelineLayout
            info.basePipelineIndex = -1
            return vkCreateComputePipelines(device, nil, 1, &info, nil, &pipeline)
        }
        guard result == VK_SUCCESS else { throw ShaderError.vulkan("compute pipeline") }
    }

    /// Linear, clamped: a distortion that samples past the edge gets the edge
    /// pixel rather than a wrapped copy of the far side.
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

    private func createDescriptorSet(imageView: VkImageView) throws {
        var sizes = [
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, descriptorCount: 1),
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

        // GENERAL is where `ComputeShaderNode.update`'s pre-dispatch barrier
        // puts the image, and what a storage binding requires.
        var imageInfo = VkDescriptorImageInfo()
        imageInfo.imageView = imageView
        imageInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL

        var bufferInfo = VkDescriptorBufferInfo()
        bufferInfo.buffer = uniforms.buffer
        bufferInfo.offset = 0
        bufferInfo.range = VkDeviceSize(MemoryLayout<ShaderUniforms>.stride)

        var argumentInfo = VkDescriptorBufferInfo()
        argumentInfo.buffer = arguments?.buffer
        argumentInfo.offset = 0
        argumentInfo.range = VkDeviceSize(VK_WHOLE_SIZE)

        withUnsafePointer(to: &imageInfo) { imagePtr in
            withUnsafePointer(to: &bufferInfo) { bufferPtr in
                withUnsafePointer(to: &argumentInfo) { argumentPtr in
                    var writeImage = VkWriteDescriptorSet()
                    writeImage.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                    writeImage.dstSet = descriptorSet
                    writeImage.dstBinding = 0
                    writeImage.descriptorCount = 1
                    writeImage.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
                    writeImage.pImageInfo = imagePtr

                    var writeUniform = VkWriteDescriptorSet()
                    writeUniform.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                    writeUniform.dstSet = descriptorSet
                    writeUniform.dstBinding = 1
                    writeUniform.descriptorCount = 1
                    writeUniform.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
                    writeUniform.pBufferInfo = bufferPtr

                    var writes = [writeImage, writeUniform]
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
        }
        // The sampled images in a pass of their own, so one code path writes
        // them whether the set is being built or rebound.
        writeInputs(inputs)
    }

    /// Write every sampled-image descriptor with `inputs`' current handles.
    /// Each image is sampled where its writer left it — the layout a canvas
    /// node, a compute slot and a `RenderTexture` all leave theirs in.
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
