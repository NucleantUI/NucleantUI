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
/// A shader in Python syntax is PyShader's: compiled when the app is built by
/// its build plugin and run with `SpirvFunction`, or compiled while it runs
/// with `PyShaderFunction` from NucleantUI_PyShader. NucleantUI itself knows
/// only SPIR-V.
///
/// It is a `ShaderProtocol` like any other: what it compiles to is its
/// `spirv`, and the `ShaderArgument`s it is handed — `Shader(_:arguments:)`,
/// `.shader(_:arguments:)` — are its `input`. A vertex + fragment pair is a
/// SPIR-V module's (`SpirvFunction`, `PyShaderFunction`).
public struct ShaderFunction: Hashable, Sendable {

    /// What the source is written in.
    public enum Language: Hashable, Sendable {
        /// GLSL 450, wrapped by `ShaderSource` and compiled by shaderc.
        case glsl
        /// SPIR-V already, compiled by something else — no source to wrap and
        /// nothing left to run through a compiler. See `init(spirv:)`.
        case spirv
    }

    public let language: Language

    /// Declarations emitted at file scope, before `main` — helper functions,
    /// constants, structs. GLSL has no nested function definitions, so
    /// anything a body *calls* has to live here rather than in the body.
    /// TouchBay's shader library splits its sources the same way
    /// (`FragShaderFunction(functions:main:)`).
    public let functions: String

    /// The per-pixel body, inlined into `main`.
    public let body: String

    /// A module compiled somewhere other than here — `nil` for every source
    /// language, which is all of them but `.spirv`.
    let precompiled: Precompiled?

    /// What there is to know about a module when there is no source to read
    /// it from: the words, and whether it moves. Hashable and Sendable like
    /// everything else here, so a `ShaderFunction` holding one is still a
    /// value.
    struct Precompiled: Hashable, Sendable {
        let words: [UInt32]
        let isAnimated: Bool
    }

    /// What the views running it hand it — `Shader(_:arguments:textures:)`,
    /// `.shader(_:arguments:textures:)`, `tex.shader(_:arguments:textures:)`:
    /// the argument values, the names of the textures it samples, and
    /// whether it reads a view with `layer(uv)`. The wrapper declares each
    /// of them, so they are part of what it compiles to; the arguments are
    /// its `input` as well. None for a function used as it is.
    var arguments: [ShaderArgument] = []
    var textureNames: [String] = []
    var samplesContent = false

    public init(functions: String = "", _ body: String) {
        self.language = .glsl
        self.functions = functions
        self.body = body
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
    /// A module's entry points say what it is, so one with a vertex +
    /// fragment pair is drawn as geometry, as `SpirvFunction`'s is.
    ///
    /// - Parameter isAnimated: whether the module reads the clock or the
    ///   pointer. There is no source to tell from, so the caller says; the
    ///   default errs towards redispatching, which only costs dispatches,
    ///   where the other way round would freeze a shader that does move.
    public init(spirv words: [UInt32], isAnimated: Bool = true) {
        self.language = .spirv
        self.functions = ""
        // There is no body: a module is not text.
        self.body = ""
        self.precompiled = Precompiled(words: words, isAnimated: isAnimated)
    }

    /// This function as a view runs it: reading `arguments`, sampling
    /// `textures` by name, and — under `.shader(_:)` or `tex.shader(_:)` —
    /// the view or texture beneath it.
    func reading(_ arguments: [ShaderArgument], textures: [ShaderTextureInput], content: Bool) -> ShaderFunction {
        var function = self
        function.arguments = arguments
        function.textureNames = textures.map(\.name)
        function.samplesContent = content
        return function
    }

    /// The text a source function is written as — what `isAnimated` reads.
    var source: String {
        [functions, body].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Whether the shader reads anything that changes between frames.
    ///
    /// A source that never mentions the clock or the pointer produces the
    /// same pixels every dispatch, so it is dispatched once — and, under
    /// `.shader(_:)`, again only when the view beneath it is repainted. A
    /// textual test, so a helper that takes `time` as a parameter counts too;
    /// erring towards "animated" only costs dispatches.
    public var isAnimated: Bool {
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
/// Every value reaches the shader as it was given. A color is its red,
/// green, blue and alpha. A light/dark pair is a `ShapeStyle.dynamic`;
/// resolve it for the view's scheme and pass its color
/// (`style.resolved(for: colorScheme).flatColor`).
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
    /// color goes in as the red, green, blue and alpha it was given.
    /// Vectors and their arrays are copied as the bytes they already are.
    func pack(into data: inout [Float]) -> Int {
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
            return Self.append(color, to: &data)
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

/// A `ShaderFunction`'s input: its `ShaderArgument`s, as its wrapper reads
/// them from binding 3 — two floats per argument (offset into the buffer,
/// element count), then every argument's values in order. `std430` gives a
/// `float[]` a 4-byte stride, so the floats are the buffer byte for byte.
///
/// The function makes it from the arguments it was handed. Nothing in it
/// changes: new values are a new function, from the view that hands them.
public final class ShaderArguments: ShaderInput {
    let arguments: [ShaderArgument]

    nonisolated init(_ arguments: [ShaderArgument]) {
        self.arguments = arguments
    }

    public func pack(into bytes: inout [UInt8]) {
        guard !arguments.isEmpty else { return }
        var header: [Float] = []
        var data: [Float] = []
        let base = arguments.count * 2
        for argument in arguments {
            header.append(Float(base + data.count))
            header.append(Float(argument.pack(into: &data)))
        }
        (header + data).withUnsafeBytes { bytes.append(contentsOf: $0) }
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

/// The textures a shader samples by name, in binding order.
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

/// A view whose pixels are produced by a shader on the GPU.
///
/// It takes whatever space it is offered, so give it a `.frame`. Unlike every
/// other view here it does not draw into the shared ThorVG canvas — it gets its
/// own image, composited into its rect. That means a shader view is never free:
/// it dispatches every frame, which is the point of it.
///
/// Generic over its `ShaderProtocol` type — a `SpirvFunction`, or a module from
/// anywhere else. A module with a compute entry point is dispatched over every
/// pixel; one with a vertex + fragment pair draws `vertices` vertices
/// `instances` times. Its input is observed: a change to it is uploaded and
/// redrawn without this view being rebuilt.
///
/// ```swift
/// Shader(SpirvFunction(spirv: words) { model.tint })
/// ```
@View
public struct Shader<Function: ShaderProtocol> {
    let function: Function
    /// Named `RenderTexture`s the shader samples — `a(uv)` in the body, or
    /// binding 4 and up in a module, in order.
    let textures: [ShaderTextureInput]
    /// What one draw covers, for a module with a vertex stage.
    let draw: ShaderDraw

    /// - Parameters:
    ///   - vertices: with a vertex stage, vertices per instance; 6 is a quad
    ///     as two triangles.
    ///   - instances: how many times the vertex stage runs over them.
    public init(
        _ function: Function,
        textures: [ShaderTextureInput] = [],
        vertices: Int = 6,
        instances: Int = 1,
        _viewID: ViewID = #viewID
    ) {
        self.function = function
        self.textures = textures
        self.draw = ShaderDraw(vertices: max(0, vertices), instances: max(0, instances))
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }
}

@MainActor
extension Shader where Function == ShaderFunction {

    /// `function` reading `arguments` — see `ShaderArgument` — and sampling
    /// `textures` by name, as `a(uv)`.
    public init(
        _ function: ShaderFunction,
        arguments: [ShaderArgument] = [],
        textures: [ShaderTextureInput] = [],
        _viewID: ViewID = #viewID
    ) {
        self.init(
            function.reading(arguments, textures: textures, content: false),
            textures: textures,
            vertices: 6,
            _viewID: _viewID
        )
    }

    public init(
        source: String,
        arguments: [ShaderArgument] = [],
        textures: [ShaderTextureInput] = [],
        _viewID: ViewID = #viewID
    ) {
        self.init(ShaderFunction(source), arguments: arguments, textures: textures, _viewID: _viewID)
    }
}

extension Shader: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        // Read once per build: compiling is the function's business, and
        // the slot compares the words it is handed every pass.
        ViewNode(content: ShaderModuleContent(
            path: context.path,
            words: function.spirv,
            input: function.input,
            isAnimated: function.isAnimated,
            draw: draw,
            textures: ShaderTextures(textures)
        ))
    }
}

/// What one draw of a module with a vertex stage covers.
struct ShaderDraw: Hashable {
    let vertices: Int
    let instances: Int
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
    static var current: ShaderSlotRegistry<NucleantRenderNode>?

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
    static weak var attached: ShaderSlotRegistry<NucleantRenderNode>?
}
