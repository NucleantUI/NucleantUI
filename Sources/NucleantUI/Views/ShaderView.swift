//
//  ShaderView.swift
//  NucleantUI
//

/// A fragment-style shader, compiled once and reused.
///
/// The body is written in the terms TouchBay's shader library uses — `uv`,
/// `fragCoord`, `time`, `resolution` and `mouse` are in scope, and it assigns
/// `fragColor`:
///
/// ```swift
/// let plasma = ShaderFunction("""
///     float v = sin(uv.x * 10.0 + time)
///             + sin((uv.y * 10.0 + time) * 0.5);
///     fragColor = vec4(vec3(0.5 + 0.5 * sin(3.14159 * v)), 1.0);
/// """)
/// ```
///
/// Source beginning with `#version` is taken as a complete GLSL 450 compute
/// shader instead, and must declare `local_size_x = 8, local_size_y = 8` plus
/// the bindings the wrapper would have (0: `writeonly image2D`, 1: the
/// `Uniforms` block).
///
/// The same shader in Python syntax goes through `ShaderFunction(pyshader:)`
/// and PyShader, which emits the SPIR-V directly — no GLSL, no shaderc.
///
/// A function may also place its own geometry: `ShaderFunction(varyings:vertex:fragment:)`
/// — or a PyShader module defining `vertex` as well as `fragment` — is a
/// vertex + fragment pair, and `isGraphics` says so. It is the same type
/// either way, so it goes into the same `.shader(_:)` and the same
/// `ShaderArgument`s; what changes is only which pixels the body runs over.
public struct ShaderFunction: Hashable, Sendable {

    /// What the source is written in.
    public enum Language: Hashable, Sendable {
        /// GLSL 450, wrapped by `ShaderSource` and compiled by shaderc.
        case glsl
        /// PyShader's Python subset, compiled to SPIR-V by the PyShader package.
        case pyshader
        /// SPIR-V already, compiled by something else — no source to wrap and
        /// nothing left to run through a compiler. See `init(spirv:)`.
        case spirv
    }

    public let language: Language

    /// Declarations emitted at file scope, before `main` — helper functions,
    /// constants, structs. GLSL has no nested function definitions, so
    /// anything a body *calls* has to live here rather than in the body.
    /// TouchBay's shader library splits its sources the same way
    /// (`FragShaderFunction(functions:main:)`). Always empty for PyShader,
    /// whose source is one Python module.
    public let functions: String

    /// The per-pixel body, inlined into `main` — or, for PyShader, the whole
    /// Python module, both stages included.
    public let body: String

    /// GLSL only: a stage that places the geometry `body` then shades, and
    /// the varyings between them. GLSL is two shaders, so a pair needs two
    /// sources.
    ///
    /// `nil` for every PyShader function, whatever it does: one module holds
    /// both stages there, so `body` is the whole of it and there is nothing
    /// to carry beside it.
    public let glslVertexStage: VertexStage?

    /// A module compiled somewhere other than here — `nil` for every source
    /// language, which is all of them but `.spirv`.
    private let precompiled: Precompiled?

    /// What there is to know about a module when there is no source to read
    /// it from: the words, an identity to compare them by, and whether it
    /// moves. Hashable and Sendable like everything else here, so a
    /// `ShaderFunction` holding one is still a value.
    struct Precompiled: Hashable, Sendable {
        let words: [UInt32]
        /// The whole module, encoded — so two different modules are two
        /// different identities rather than two that merely hash apart.
        /// Worked out once, because `source` is compared every frame and a
        /// module is far larger than the text a source function is compared
        /// by.
        let identity: String
        let isAnimated: Bool
    }

    /// The module itself, when `language` is `.spirv`; empty otherwise.
    ///
    /// Nothing compiles this — it is handed to `vkCreateShaderModule` as it
    /// stands — so it has to already meet the compute contract the pipeline
    /// binds against (see `ShaderCode`), which is the same contract a
    /// PyShader module compiled for `.computeImage` meets.
    public var spirv: [UInt32] { precompiled?.words ?? [] }

    /// The GLSL vertex half of a pair.
    public struct VertexStage: Hashable, Sendable {
        /// `type name;` pairs the vertex stage writes and the fragment stage
        /// reads, declared once for both (`flat` is added for integer types).
        public let varyings: String
        /// The body, placing its geometry from `gl_VertexIndex` /
        /// `gl_InstanceIndex` and writing `gl_Position` in y-up clip space.
        public let body: String
    }

    public init(functions: String = "", _ body: String) {
        self.language = .glsl
        self.functions = functions
        self.body = body
        self.glslVertexStage = nil
        self.precompiled = nil
    }

    /// A vertex + fragment pair in GLSL.
    ///
    /// Where a per-pixel body runs once per pixel of the whole rect, this
    /// runs `vertex` once per vertex of every instance drawn and `fragment`
    /// once per pixel the resulting triangles cover — which is what makes
    /// "one quad per touch, from an array of touches" a single draw call.
    /// There are no vertex buffers: the vertex stage places its geometry from
    /// `gl_VertexIndex`, `gl_InstanceIndex` and the `ShaderArgument`s.
    ///
    /// `varyings` is what connects the two — `type name;` pairs, declared
    /// once and used as plain variables in both stages (`flat` is added for
    /// integer types):
    ///
    /// ```swift
    /// let glow = ShaderFunction(
    ///     varyings: "vec2 local; float seed;",
    ///     vertex: """
    ///         int t = gl_InstanceIndex * 3;
    ///         vec2 corner = QUAD[gl_VertexIndex];
    ///         vec2 centre = vec2(touches(t), touches(t + 1));
    ///         gl_Position = vec4((centre + corner * 0.25) * 2.0 - 1.0, 0.0, 1.0);
    ///         local = corner * 0.5 + 0.5;
    ///         seed = touches(t + 2);
    ///     """,
    ///     fragment: """
    ///         float d = distance(local, vec2(0.5));
    ///         fragColor = vec4(vec3(fract(seed + time)), smoothstep(0.5, 0.0, d));
    ///     """)
    /// ```
    ///
    /// `time`, `resolution` and `mouse` are in scope in both stages, as are
    /// the arguments; `uv` and `fragCoord` in the fragment stage, and
    /// `layer(uv)` there too when the function is used as a `.shader(_:)`
    /// effect. Shader space is y-up as everywhere else: `gl_Position` is
    /// written as in OpenGL and flipped into Vulkan's clip space by the
    /// wrapper.
    public init(functions: String = "", varyings: String = "", vertex: String, fragment: String) {
        self.language = .glsl
        self.functions = functions
        self.body = fragment
        self.glslVertexStage = VertexStage(varyings: varyings, body: vertex)
        self.precompiled = nil
    }

    /// A shader written in Python syntax, compiled by PyShader.
    ///
    /// The module defines `def main(...) -> float4` and takes what it needs by
    /// parameter name: `uv`, `frag_coord`, `pixel`, `time`, `time_delta`,
    /// `frame`, `resolution`, `mouse`, `mouse_click`, plus every
    /// `ShaderArgument` by its name (a `.floatArray` arrives as a `FloatArray`,
    /// a `.float2Array` as a `Float2Array` and so on — `a[i]` and `len(a)`).
    /// Under `.shader(_:)`, `layer(uv)` reads the
    /// view's own pixels as it does in GLSL. Helper functions, module
    /// constants and lambdas live in the same source:
    ///
    /// ```swift
    /// let plasma = ShaderFunction(pyshader: """
    ///     def main(uv: float2, time: float) -> float4:
    ///         v = sin(uv.x * 10.0 + time) + sin((uv.y * 10.0 + time) * 0.5)
    ///         return float4(float3(0.5 + 0.5 * sin(3.14159 * v)), 1.0)
    /// """)
    /// ```
    /// A PyShader module defining both `vertex` and `fragment` is a vertex +
    /// fragment pair instead: `vertex` returns a `class` whose first field is
    /// the `float4` position and whose other fields are the varyings, taken by
    /// `fragment` by name.
    ///
    /// ```swift
    /// let glow = ShaderFunction(pyshader: """
    ///     class V:
    ///         position: float4
    ///         local: float2
    ///         seed: float
    ///
    ///     def vertex(vertex_index: int, instance_index: int, touches: Float4Array) -> V:
    ///         ...
    ///
    ///     def fragment(local: float2, seed: float, time: float) -> float4:
    ///         ...
    /// """)
    /// ```
    public init(pyshader source: String) {
        self.language = .pyshader
        self.functions = ""
        self.body = source
        self.glslVertexStage = nil
        self.precompiled = nil
    }

    /// Wraps an unmodified ShaderToy shader.
    ///
    /// Paste the whole thing — helper functions and its
    /// `void mainImage(out vec4 fragColor, in vec2 fragCoord)` — and it is
    /// emitted at file scope and called once per pixel. `iTime`, `iTimeDelta`,
    /// `iFrame`, `iResolution` and `iMouse` are already declared with
    /// ShaderToy's own types, so most shaders compile untouched:
    ///
    /// ```swift
    /// ShaderFunction(shaderToy: """
    ///     void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    ///         vec2 uv = fragCoord / iResolution.xy;
    ///         fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
    ///     }
    /// """)
    /// ```
    ///
    /// What will *not* compile, because the target is a compute shader rather
    /// than a fragment one: `iChannel0`…`iChannel3` and any `texture()` call
    /// against them, and the screen-space derivatives (`fwidth`, `dFdx`,
    /// `dFdy`). A shader using those needs reworking, not just wrapping.
    /// `gl_FragCoord` is likewise absent — `mainImage`'s own `fragCoord`
    /// parameter carries the same value.
    public init(shaderToy source: String) {
        self.language = .glsl
        self.functions = source
        self.body = "mainImage(fragColor, fragCoord);"
        self.glslVertexStage = nil
        self.precompiled = nil
    }

    /// A module that is already SPIR-V, compiled by something other than
    /// this framework.
    ///
    /// The words go to `vkCreateShaderModule` untouched: nothing here wraps
    /// them, renames an entry point or rewrites a binding. So the module has
    /// to already be built against the layout the compute pipeline binds —
    /// the storage image written one pixel per invocation at binding 0, the
    /// `Uniforms` block with the clock and the pointer at binding 1, the
    /// view's own pixels at binding 2, the arguments at binding 3, and a
    /// `sampler2D` per named texture from binding 4 up — with `main` as its
    /// entry point. That is `ComputeImageInterface.nucleantUI`'s layout, so
    /// anything emitting against *it* drops in here, which is what this
    /// initializer is for: a shader built out of something that is not text,
    /// such as a node graph, rather than written as a source language.
    ///
    /// It is a compute function. A vertex + fragment pair is two modules and
    /// two entry points, which this does not carry, so `isGraphics` is always
    /// `false` — pass a graphics shader as PyShader or GLSL.
    ///
    /// - Parameter isAnimated: whether the module reads the clock or the
    ///   pointer. There is no source to tell from, so the caller says; the
    ///   default errs towards redispatching, which only costs dispatches,
    ///   where the other way round would freeze a shader that does move.
    public init(spirv words: [UInt32], isAnimated: Bool = true) {
        self.language = .spirv
        self.functions = ""
        // There is no body: a module is not text. What the cache compares
        // is built once, below.
        self.body = ""
        self.glslVertexStage = nil
        self.precompiled = Precompiled(
            words: words,
            identity: Self.identity(of: words),
            isAnimated: isAnimated
        )
    }

    /// Every word, in hex, under the language's own prefix — what `source`
    /// answers for a precompiled module. No Foundation and no digest: this
    /// is an identity the pipeline cache tests for equality, so a module
    /// that differs anywhere has to differ here.
    private static func identity(of words: [UInt32]) -> String {
        var text = "#spirv\n"
        text.reserveCapacity(words.count * 8 + 8)
        let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7",
                                   "8", "9", "a", "b", "c", "d", "e", "f"]
        for word in words {
            var shift = 28
            while shift >= 0 {
                text.append(digits[Int((word >> UInt32(shift)) & 0xF)])
                shift -= 4
            }
        }
        return text
    }

    /// Whether this function places its own geometry — a `glslVertexStage`,
    /// or a `def vertex` beside a `def fragment` in one PyShader module. The
    /// host draws it with a graphics pipeline rather than a compute dispatch,
    /// and it is the same `ShaderFunction` either way, so `.shader(_:)` takes
    /// it as it takes any other.
    public var isGraphics: Bool {
        switch language {
        case .glsl:
            return glslVertexStage != nil
        case .pyshader:
            return Self.definesStage("vertex", in: body) && Self.definesStage("fragment", in: body)
        case .spirv:
            // One module, one entry point — see `init(spirv:)`.
            return false
        }
    }

    /// `def <name>(` at the start of a line of PyShader source.
    static func definesStage(_ name: String, in source: String) -> Bool {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.drop(while: { $0 == " " || $0 == "\t" })
            guard text.hasPrefix("def ") else { continue }
            let rest = text.dropFirst(4).drop(while: { $0 == " " })
            if rest.hasPrefix(name), rest.dropFirst(name.count).drop(while: { $0 == " " }).hasPrefix("(") {
                return true
            }
        }
        return false
    }

    /// Identity for the compiled-pipeline cache: both halves, since either
    /// changing means a recompile — and the language, since the same text
    /// means different things in each.
    var source: String {
        let stage = glslVertexStage.map { [$0.varyings, $0.body] } ?? []
        let text = ([functions] + stage + [body]).filter { !$0.isEmpty }.joined(separator: "\n")
        switch language {
        case .glsl:     return text
        case .pyshader: return "#pyshader\n" + text
        // `body` is the module, encoded — the whole of it, so two different
        // modules are two different identities rather than two that merely
        // hash apart.
        // Already carries its own prefix, and nothing else to join it to.
        case .spirv:    return precompiled?.identity ?? "#spirv\n"
        }
    }

    /// Whether the shader reads anything that changes between frames.
    ///
    /// A source that never mentions the clock or the pointer produces the
    /// same pixels every dispatch, so it is dispatched once — and, under
    /// `.shader(_:)`, again only when the view beneath it is repainted. A
    /// textual test, so a helper that takes `time` as a parameter counts too;
    /// erring towards "animated" only costs dispatches.
    var isAnimated: Bool {
        precompiled?.isAnimated ?? Self.mentionsClock(source)
    }

    /// Whether `source` names any per-frame input, as an identifier.
    static func mentionsClock(_ source: String) -> Bool {
        let clocks: Set<Substring> = [
            "time", "iTime", "iTimeDelta", "iFrame", "mouse", "iMouse",
            // PyShader's spellings of the same inputs.
            "time_delta", "frame", "mouse_click",
        ]
        var identifier = Substring()
        for character in source {
            if character.isLetter || character.isNumber || character == "_" {
                identifier.append(character)
            } else {
                if clocks.contains(identifier) { return true }
                identifier = Substring()
            }
        }
        return clocks.contains(identifier)
    }
}

/// Two, three and four floats, laid out as the GPU reads them.
///
/// Plain `Float` fields and nothing else, so an array of them is the byte
/// image of a `vec2[]`/`vec3[]`/`vec4[]` and is copied into the argument
/// buffer whole rather than a component at a time.
public struct Float2: Hashable, Sendable {
    public var v1: Float
    public var v2: Float

    public init(_ v1: Float, _ v2: Float) {
        self.v1 = v1
        self.v2 = v2
    }
    
    public init<F: BinaryFloatingPoint>(_ v1: F, _ v2: F) {
        self.v1 = .init(v1)
        self.v2 = .init(v2)
    }
    
    
}


public struct Float3: Hashable, Sendable {
    public var v1: Float
    public var v2: Float
    public var v3: Float

    public init(_ v1: Float, _ v2: Float, _ v3: Float) {
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
    }
    
    public init<F: BinaryFloatingPoint>(_ v1: F, _ v2: F, _ v3: F) {
        self.v1 = .init(v1)
        self.v2 = .init(v2)
        self.v3 = .init(v3)
    }
}

public struct Float4: Hashable, Sendable {
    public var v1: Float
    public var v2: Float
    public var v3: Float
    public var v4: Float

    public init(_ v1: Float, _ v2: Float, _ v3: Float, _ v4: Float) {
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.v4 = v4
    }
    
    public init<F: BinaryFloatingPoint>(_ v1: F, _ v2: F, _ v3: F, _ v4: F) {
        self.v1 = .init(v1)
        self.v2 = .init(v2)
        self.v3 = .init(v3)
        self.v4 = .init(v4)
    }
}

/// A value handed to a shader from Swift — SwiftUI's `Shader.Argument`.
///
/// Each one is named, and the name is what the GLSL body sees:
///
/// ```swift
/// Shader(envelope, arguments: [
///     .float("gain", 1.5),                   // float gain;
///     .float2("size", Float2(w, h)),         // vec2  size;
///     .color("tint", .orange),               // vec4  tint;
///     .floatArray("mins", negatives),        // float mins(int i); int minsCount;
///     .float2Array("points", points),        // vec2  points(int i); int pointsCount;
/// ])
/// ```
///
/// Scalars and vectors are plain variables; an array is read through a
/// function of its index, with its length beside it, because a storage
/// buffer's contents cannot be aliased as a GLSL array variable. Reads
/// outside the array are clamped to its ends, and an empty array reads
/// as zero.
///
/// Arguments live in a storage buffer the shader reads (binding 3), so an
/// array can be as long as it likes — a waveform's ten thousand points are
/// fine. Changing a value re-dispatches the shader, whether or not it is
/// animated; the set of names and kinds is part of the compiled pipeline's
/// identity, so keep those stable across rebuilds and vary only the values.
public enum ShaderArgument: Hashable, Sendable {
    case float(String, Float)
    case float2(String, Float2)
    case float3(String, Float3)
    case float4(String, Float4)
    case color(String, Color)
    case floatArray(String, [Float])
    case float2Array(String, [Float2])
    case float3Array(String, [Float3])
    case float4Array(String, [Float4])

    public var name: String {
        switch self {
        case .float(let name, _), .float2(let name, _), .float3(let name, _), .float4(let name, _),
             .color(let name, _), .floatArray(let name, _), .float2Array(let name, _),
             .float3Array(let name, _), .float4Array(let name, _):
            return name
        }
    }

    /// The GLSL declaration this argument becomes; `[]` marks an array of
    /// the element type.
    var glslType: String {
        switch self {
        case .float:       return "float"
        case .float2:      return "vec2"
        case .float3:      return "vec3"
        case .float4:      return "vec4"
        case .color:       return "vec4"
        case .floatArray:  return "float[]"
        case .float2Array: return "vec2[]"
        case .float3Array: return "vec3[]"
        case .float4Array: return "vec4[]"
        }
    }

    /// Appends the value's floats to `data` and returns how many elements
    /// went in — one for a scalar or vector, the length for an array. A
    /// color is resolved for `scheme` first, so a dynamic one reaches the
    /// shader in the appearance the view is drawn under. Vectors and their
    /// arrays are copied as the bytes they already are.
    func pack(into data: inout [Float], for scheme: ColorScheme) -> Int {
        switch self {
        case .float(_, let x):
            data.append(x)
            return 1
        case .float2(_, let v):
            return Self.append(v, to: &data)
        case .float3(_, let v):
            return Self.append(v, to: &data)
        case .float4(_, let v):
            return Self.append(v, to: &data)
        case .color(_, let color):
            let resolved = color.resolved(for: scheme)
            data.append(contentsOf: [Float(resolved.red), Float(resolved.green), Float(resolved.blue), Float(resolved.alpha)])
            return 1
        case .floatArray(_, let array):
            data.append(contentsOf: array)
            return array.count
        case .float2Array(_, let array):
            return Self.append(array, to: &data)
        case .float3Array(_, let array):
            return Self.append(array, to: &data)
        case .float4Array(_, let array):
            return Self.append(array, to: &data)
        }
    }

    private static func append<V>(_ value: V, to data: inout [Float]) -> Int {
        append([value], to: &data)
    }

    /// The array's storage, reinterpreted as floats. Holds because `Float2`,
    /// `Float3` and `Float4` are nothing but `Float` fields: their stride is
    /// their size, so consecutive elements are consecutive floats.
    private static func append<V>(_ array: [V], to data: inout [Float]) -> Int {
        assert(MemoryLayout<V>.stride == MemoryLayout<V>.size && MemoryLayout<V>.size % MemoryLayout<Float>.size == 0)
        array.withUnsafeBytes { bytes in
            data.append(contentsOf: bytes.bindMemory(to: Float.self))
        }
        return array.count
    }
}

/// A list of arguments, as the pipeline consumes it: the part that shapes
/// the compiled shader (names and kinds) apart from the part that only fills
/// a buffer (the numbers).
struct ShaderArguments: Equatable {
    /// `name:type` per argument — the GLSL declarations depend on nothing else.
    let signature: String
    let declarations: [(name: String, type: String)]
    /// Two floats per argument (offset into `packed`, element count), then
    /// every argument's values in order. `std430` gives a `float[]` a 4-byte
    /// stride, so this is the buffer byte for byte.
    let packed: [Float]

    init(_ arguments: [ShaderArgument], colorScheme: ColorScheme = .light) {
        declarations = arguments.map { ($0.name, $0.glslType) }
        signature = declarations.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        var header: [Float] = []
        var data: [Float] = []
        let base = arguments.count * 2
        for argument in arguments {
            header.append(Float(base + data.count))
            header.append(Float(argument.pack(into: &data, for: colorScheme)))
        }
        packed = header + data
    }

    static let none = ShaderArguments([])

    var isEmpty: Bool { declarations.isEmpty }

    static func == (lhs: ShaderArguments, rhs: ShaderArguments) -> Bool {
        lhs.signature == rhs.signature && lhs.packed == rhs.packed
    }
}

/// One `RenderTexture` handed to a shader under a name.
///
/// ```swift
/// Shader(mix, arguments: [.float("blend", t)],
///                textures: [.init("a", layerA), .init("b", layerB)])
/// ```
///
/// In the shader body the texture is a callable: `a(uv)` samples it and
/// `a_size` is its pixel size. `layer(uv)` keeps meaning "the view this
/// effect is applied to", so nothing written against it changes meaning.
///
/// Not a `ShaderArgument`: an argument is a value packed into one float
/// buffer, and a texture is an image that belongs in a descriptor of its own.
public struct ShaderTextureInput: Hashable, @unchecked Sendable {
    /// The name the shader knows it by.
    public let name: String
    public let texture: RenderTexture

    public init(_ name: String, _ texture: RenderTexture) {
        self.name = name
        self.texture = texture
    }

    /// By name and by texture identity — what the pixels are is not part of
    /// it, the same way a `RenderTexture` compares as a view input.
    public static func == (lhs: ShaderTextureInput, rhs: ShaderTextureInput) -> Bool {
        lhs.name == rhs.name && lhs.texture === rhs.texture
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ObjectIdentifier(texture))
    }
}

/// The textures a shader samples by name, in binding order — the companion to
/// `ShaderArguments`.
///
/// Bindings start at 4: 0 is the output image, 1 the uniforms, 2 the content
/// (`layer(uv)`), 3 the argument buffer. A changed *set* — names, order,
/// count — changes the compiled shader, so it is in the slot's identity; a
/// texture that merely has a different image is a descriptor rebind.
struct ShaderTextures: Equatable {
    let inputs: [ShaderTextureInput]
    /// The names in binding order: what the shader was compiled against.
    let signature: String

    init(_ inputs: [ShaderTextureInput] = []) {
        self.inputs = inputs
        self.signature = inputs.map(\.name).joined(separator: ",")
    }

    static let none = ShaderTextures()

    var isEmpty: Bool { inputs.isEmpty }

    /// Every texture has an image to bind: one that has never rendered takes
    /// its canvas here. Called from inside a layout pass, which is why it
    /// rasterizes the list the texture already holds rather than walking the
    /// tree again — one tree at a time, as `OffscreenRender` says.
    @MainActor
    func prepare() {
        for input in inputs { input.texture.prepareImage() }
    }

    /// What each texture's `generation` is now. A texture that rendered again
    /// re-dispatches the shader reading it, the way new content in a
    /// `.shader` layer re-arms one.
    @MainActor
    var generations: [Int] { inputs.map(\.texture.generation) }

    /// The image views to bind, in binding order, or `nil` while any of the
    /// textures has no image yet — a slot cannot be built against a texture
    /// that has not rendered.
    @MainActor
    var imageInputs: [ShaderImageInput]? {
        var bound: [ShaderImageInput] = []
        for (index, input) in inputs.enumerated() {
            guard let image = input.texture.gpuImage else { return nil }
            bound.append(.texture(input.name, image.view, at: index))
        }
        return bound
    }

    static func == (lhs: ShaderTextures, rhs: ShaderTextures) -> Bool {
        lhs.inputs == rhs.inputs
    }
}

/// A view whose pixels are produced by a compute shader on the GPU.
///
/// It takes whatever space it is offered, so give it a `.frame`. Unlike every
/// other view here it does not draw into the shared ThorVG canvas — it gets its
/// own image, composited into its rect. That means a shader view is never free:
/// it dispatches every frame, which is the point of it.
@View
public struct Shader: View {
    let function: ShaderFunction
    let arguments: [ShaderArgument]
    /// Named `RenderTexture`s the shader samples — `a(uv)` in the body.
    let textures: [ShaderTextureInput]

    public init(
        _ function: ShaderFunction,
        arguments: [ShaderArgument] = [],
        textures: [ShaderTextureInput] = [],
        _viewID: ViewID = #viewID
    ) {
        self.function = function
        self.arguments = arguments
        self.textures = textures
        self._viewID = _viewID
    }

    public init(
        source: String,
        arguments: [ShaderArgument] = [],
        textures: [ShaderTextureInput] = [],
        _viewID: ViewID = #viewID
    ) {
        self.function = ShaderFunction(source)
        self.arguments = arguments
        self.textures = textures
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }
}

extension Shader: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        ViewNode(content: ShaderContent(
            // The structural path is the slot's identity, so the compiled
            // pipeline survives rebuilds and is torn down only when this view
            // actually leaves the tree.
            path: context.path,
            function: function,
            arguments: ShaderArguments(arguments, colorScheme: context.environment.colorScheme),
            textures: ShaderTextures(textures)
        ))
    }
}

/// Reserves a GPU slot and reports where it should composite. Emits no draw
/// commands of its own — its pixels arrive through the engine, not the canvas.
struct ShaderContent: NodeContent {
    let path: [Int]
    let function: ShaderFunction
    let arguments: ShaderArguments
    let textures: ShaderTextures

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0, let host = ShaderHost.current else { return }
        host.use(
            path: path,
            function: function,
            arguments: arguments,
            textures: textures,
            rect: rect,
            clip: context.compositeClip
        )
        host.boundaries.noteNested(at: list.commands.count, rect: context.compositeClip.map { rect.intersection($0) } ?? rect)
    }
}

/// The registry the current layout pass should talk to.
///
/// `place` is deep inside the layout walk and has no route to the window, and
/// threading a registry through `DrawContext` would put a GPU concern into the
/// one type every leaf copies. A single current-host reference, set around the
/// pass by `ViewHost`, keeps it out of the layout types entirely.
@MainActor
enum ShaderHost {
    /// The registry of the pass being laid out — `nil` outside a pass, which
    /// is also how anything offscreen knows it is not in one.
    static var current: ShaderSlotRegistry?

    /// The registry of the window that is up, pass or no pass.
    ///
    /// `current` is scoped to a layout walk, and a `RenderTexture` is made and
    /// re-rendered from wherever a model happens to live — outside any pass,
    /// before the first one, after the last. This is what it reaches for, set
    /// when the window attaches its canvas and cleared when the registry is
    /// torn down. One window's, as with every other global here
    /// (`Invalidator.shared`, `AnimationStore.current`): a second window's
    /// textures would need a registry threaded to them instead.
    ///
    /// Weak: the window owns its registry, and a window that has gone leaves
    /// this nil rather than a registry whose engine is dead.
    static weak var attached: ShaderSlotRegistry?
}
