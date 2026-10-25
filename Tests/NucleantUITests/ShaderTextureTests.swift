//
//  ShaderTextureTests.swift
//  NucleantUITests
//
//  Named textures as shader inputs: what the view layer hands the pipeline,
//  and what each inlet declares for it.
//
//  No `NucleantRenderEngine` in this target, so the descriptor writes
//  themselves are verified in the demo. What is covered here is everything
//  that decides them: the bindings, the identity that chooses rebuild over
//  rebind, the generation that re-dispatches a static shader, the GLSL
//  wrapper that has to keep saying the same thing, `ShaderFunction` as the
//  module it compiles to and the arguments it reads, and a module that
//  arrived already compiled.
//

import Foundation
import Testing
@testable import NucleantUI

@View
private struct Fill {
    let level: Int

    var body: some View {
        Color(red: Float(level) / 10, green: 0, blue: 0)
    }
}

@MainActor
@Suite(.serialized)
struct ShaderTextureInputs {

    private func texture(_ level: Int) -> RenderTexture {
        renderTexture(size: Size(width: 8, height: 8)) { Fill(level: level) }
    }

    /// 0 is the output image, 1 the uniforms, 2 the content, 3 the arguments —
    /// so the first named texture is 4.
    @Test
    func texturesAreDeclaredFromBindingFour() {
        let set = ShaderTextures([.init("a", texture(1)), .init("b", texture(2))])
        #expect(set.signature == "a,b")
        let glsl = ShaderSource.textureSource(["a", "b"])
        #expect(glsl.contains("layout(binding = 4) uniform sampler2D uTex_a;"))
        #expect(glsl.contains("layout(binding = 5) uniform sampler2D uTex_b;"))
        // Every `RenderTexture` is a canvas image, stored top-down.
        #expect(glsl.contains("vec2(p.x, 1.0 - p.y)"))
    }

    @Test
    func noTexturesIsNoDeclarations() {
        #expect(ShaderTextures.none.isEmpty)
        #expect(ShaderTextures.none.signature == "")
        #expect(ShaderTextures.none.imageInputs?.isEmpty == true)
    }

    /// The set is compared by name and by *which* texture, not by its pixels:
    /// a texture that merely drew again must not rebuild the pipeline.
    @Test
    func identityIsNameAndTexture() {
        let a = texture(1), b = texture(2)
        #expect(ShaderTextures([.init("x", a)]) == ShaderTextures([.init("x", a)]))
        #expect(ShaderTextures([.init("x", a)]) != ShaderTextures([.init("x", b)]))
        #expect(ShaderTextures([.init("x", a)]) != ShaderTextures([.init("y", a)]))
        // Order is binding order, so swapping two is a different shader.
        let both = ShaderTextures([.init("x", a), .init("y", b)])
        #expect(both != ShaderTextures([.init("y", b), .init("x", a)]))
        a.render()
        #expect(ShaderTextures([.init("x", a)]) == ShaderTextures([.init("x", a)]))
    }

    /// What tells a static shader its input changed. The signature cannot:
    /// it is the same texture under the same name either way.
    @Test
    func aRenderBumpsTheGeneration() {
        let a = texture(1)
        let set = ShaderTextures([.init("a", a)])
        let before = set.generations
        a.render()
        #expect(set.generations != before)
        #expect(set.generations == [before[0] + 1])
    }

    /// With no engine there is no image, so there is nothing to bind and the
    /// slot is not built — rather than built against a dangling handle.
    @Test
    func withNoImageThereAreNoInputsToBind() {
        let set = ShaderTextures([.init("a", texture(1))])
        set.prepare()
        #expect(set.imageInputs == nil)
    }
}

/// The GLSL inlet: it declares the same names and bindings a module samples
/// its textures by, and reads every image top-down, as a module does.
@Suite
struct ShaderTextureGLSL {

    @Test
    func theComputeWrapperDeclaresEachTexture() {
        let source = ShaderSource.compute(
            functions: "",
            body: "fragColor = a(uv) * b(uv);",
            textures: ["a", "b"]
        )
        #expect(source.contains("layout(binding = 4) uniform sampler2D uTex_a;"))
        #expect(source.contains("layout(binding = 5) uniform sampler2D uTex_b;"))
        #expect(source.contains("vec4 a(vec2 p) { return texture(uTex_a, vec2(p.x, 1.0 - p.y)); }"))
        #expect(source.contains("#define a_size textureSize(uTex_a, 0)"))
        #expect(source.contains("#define b_size textureSize(uTex_b, 0)"))
    }

    /// Binding 2 is the content and is still `uContent`/`layer(uv)`: adding
    /// textures does not move what an effect already reads. Stored top-down
    /// like every image a module samples, so `layer(uv)` flips the read.
    @Test
    func texturesSitBesideTheContent() {
        let source = ShaderSource.compute(
            functions: "",
            body: "fragColor = layer(uv) + a(uv);",
            samplesContent: true,
            textures: ["a"]
        )
        #expect(source.contains("layout(binding = 2) uniform sampler2D uContent;"))
        #expect(source.contains("vec4 layer(vec2 p) { return texture(uContent, vec2(p.x, 1.0 - p.y)); }"))
        #expect(source.contains("layout(binding = 4) uniform sampler2D uTex_a;"))
    }

    @Test
    func noTexturesDeclaresNoSampler() {
        let source = ShaderSource.compute(functions: "", body: "fragColor = vec4(1.0);")
        #expect(!source.contains("uTex_"))
        #expect(!source.contains("uContent"))
    }

    /// ShaderToy's `texture(iChannel0, uv)` reads the view upright too: the
    /// wrapper's own `texture` for it flips the read as `layer(uv)` does, and
    /// the post-process compiles unchanged.
    @Test
    func iChannel0ReadsTheViewUpright() {
        let post = ShaderLibrary.shaderToyPost.reading([], textures: [], content: true)
        let source = ShaderSource.compute(
            functions: post.functions,
            body: post.body,
            samplesContent: true
        )
        #expect(source.contains("vec4 texture(NucleantContent c, vec2 p) { return layer(p); }"))
        #expect(!post.spirv.isEmpty, "a ShaderToy post-process compiles against the content as it is")
    }
}

/// `ShaderFunction` as a `ShaderProtocol`: the arguments it is handed are its
/// input, packed as its wrapper reads them, and what it compiles to declares
/// what it was handed.
@MainActor
@Suite(.serialized)
struct ShaderFunctionAsAModule {

    private func floats(_ bytes: [UInt8]) -> [Float] {
        bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func packed(_ function: ShaderFunction) -> [UInt8] {
        var bytes: [UInt8] = []
        function.input.pack(into: &bytes)
        return bytes
    }

    /// Two floats per argument — offset, count — then the values.
    @Test
    func theArgumentsAreItsInput() {
        let function = ShaderFunction("fragColor = vec4(gain);")
            .reading([.float("gain", 1.5), .floatArray("xs", [2, 3])], textures: [], content: false)
        #expect(floats(packed(function)) == [4, 1, 5, 2, 1.5, 2, 3])
    }

    @Test
    func noArgumentsPackNothing() {
        #expect(packed(ShaderFunction("fragColor = vec4(1.0);")).isEmpty)
    }

    /// A color reaches the shader as it was given. A light/dark pair is a
    /// `ShapeStyle`; the caller resolves it for its scheme and passes the
    /// color.
    @Test
    func aColorIsPackedAsItWasGiven() {
        let tint = ShapeStyle.dynamic(light: Color(red: 1, green: 0, blue: 0), dark: Color(red: 0, green: 0, blue: 1, opacity: 0.5))
        let given = ShaderFunction("fragColor = tint;").reading([.color("tint", Color(red: 1, green: 0, blue: 0))], textures: [], content: false)
        #expect(Array(floats(packed(given)).suffix(4)) == [1, 0, 0, 1])
        let resolved = ShaderFunction("fragColor = tint;").reading([.color("tint", tint.resolved(for: .dark).flatColor)], textures: [], content: false)
        #expect(Array(floats(packed(resolved)).suffix(4)) == [0, 0, 1, 0.5])
    }

    /// What it was handed is declared, so it is in what it compiles to: a
    /// body reading an argument, a texture and the view compiles only once
    /// they are there.
    @Test
    func itCompilesForWhatItWasHanded() {
        let mix = ShaderFunction("fragColor = mix(layer(uv), a(uv), blend);")
        #expect(mix.spirv.isEmpty, "nothing declares `layer`, `a` or `blend`")
        let tex = renderTexture(size: Size(width: 4, height: 4)) { Fill(level: 1) }
        let handed = mix.reading([.float("blend", 0.5)], textures: [.init("a", tex)], content: true)
        let stages = SpirvEntryPoints(handed.spirv)
        #expect(stages.compute == "main")
        #expect(!stages.isGraphics)
    }

    /// New values are a new function — the view's key — but not a new
    /// module: the declarations depend on names and kinds only.
    @Test
    func newValuesAreTheSameModule() {
        let base = ShaderFunction("fragColor = vec4(gain);")
        let one = base.reading([.float("gain", 1)], textures: [], content: false)
        let two = base.reading([.float("gain", 2)], textures: [], content: false)
        #expect(one != two)
        #expect(one.spirv == two.spirv)
    }
}

/// A module compiled somewhere else: its words are what it compiles to, and
/// its entry points say what it is.
@MainActor
@Suite(.serialized)
struct PrecompiledShaderFunctionTests {

    @Test
    func theWordsGoThroughUntouched() {
        let words = Fixture.compute
        #expect(ShaderFunction(spirv: words).spirv == words)
        // What a view hands it describes what to *generate*; a module
        // already declares what it reads, so nothing changes.
        let handed = ShaderFunction(spirv: words).reading([.float("blend", 0.5)], textures: [], content: true)
        #expect(handed.spirv == words)
    }

    /// A vertex + fragment module is drawn as geometry, whatever carries it.
    @Test
    func aPairIsReadFromTheModule() {
        #expect(!SpirvEntryPoints(ShaderFunction(spirv: Fixture.compute).spirv).isGraphics)
        #expect(SpirvEntryPoints(ShaderFunction(spirv: Fixture.graphics).spirv).isGraphics)
    }

    @Test
    func twoModulesAreTwoValues() {
        let words = Fixture.compute
        var changed = words
        changed[changed.count - 1] &+= 1
        #expect(ShaderFunction(spirv: words) == ShaderFunction(spirv: words))
        #expect(ShaderFunction(spirv: words) != ShaderFunction(spirv: changed), "one word apart is a different shader")
    }

    /// `isAnimated` is grepped out of the source for a language; here the
    /// caller says, because there is no source to grep.
    @Test
    func whatIsNormallyReadFromTheTextIsStated() {
        #expect(ShaderFunction(spirv: Fixture.compute).isAnimated, "the default errs towards redispatching")
        #expect(ShaderFunction(spirv: Fixture.compute, isAnimated: false).isAnimated == false)
    }

    @Test
    func anEmptyModuleIsStillAValue() {
        #expect(ShaderFunction(spirv: []).spirv.isEmpty)
        #expect(ShaderFunction(spirv: []).input.arguments.isEmpty)
    }
}
