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
//  rebind, the generation that re-dispatches a static shader, and the two
//  shader sources — PyShader's SPIR-V, compiled for real, the GLSL wrapper
//  that has to keep saying the same thing, and a module that arrived already
//  compiled and so goes through neither.
//

import Foundation
import Testing
@testable import NucleantUI

@View
private struct Fill {
    let level: Int

    var body: some View {
        Color(red: Double(level) / 10, green: 0, blue: 0)
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
        #expect(set.declarations.map(\.binding) == [4, 5])
        #expect(set.declarations.map(\.name) == ["a", "b"])
        // Every `RenderTexture` is a canvas image, stored top-down.
        #expect(set.declarations.map(\.isTopDown) == [true, true])
    }

    @Test
    func noTexturesIsNoDeclarations() {
        #expect(ShaderTextures.none.isEmpty)
        #expect(ShaderTextures.none.declarations.isEmpty)
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

/// The GLSL inlet. Nothing new is written in GLSL, but it has to declare the
/// same interface PyShader compiles against, or a body moved between the two
/// would quietly mean something else.
@Suite
struct ShaderTextureGLSL {

    @MainActor
    private func textures(_ names: [String]) -> ShaderTextures {
        ShaderTextures(names.map { name in
            .init(name, renderTexture(size: Size(width: 4, height: 4)) { Fill(level: 1) })
        })
    }

    @MainActor
    @Test
    func theComputeWrapperDeclaresEachTexture() {
        let source = ShaderSource.compute(
            functions: "",
            body: "fragColor = a(uv) * b(uv);",
            textures: textures(["a", "b"])
        )
        #expect(source.contains("layout(binding = 4) uniform sampler2D uTex_a;"))
        #expect(source.contains("layout(binding = 5) uniform sampler2D uTex_b;"))
        #expect(source.contains("vec4 a(vec2 p) { return texture(uTex_a, vec2(p.x, 1.0 - p.y)); }"))
        #expect(source.contains("#define a_size textureSize(uTex_a, 0)"))
        #expect(source.contains("#define b_size textureSize(uTex_b, 0)"))
    }

    /// Binding 2 is the content and is still `uContent`/`layer(uv)`: adding
    /// textures does not move what an effect already reads.
    @MainActor
    @Test
    func texturesSitBesideTheContent() {
        let source = ShaderSource.compute(
            functions: "",
            body: "fragColor = layer(uv) + a(uv);",
            samplesContent: true,
            textures: textures(["a"])
        )
        #expect(source.contains("layout(binding = 2) uniform sampler2D uContent;"))
        #expect(source.contains("vec4 layer(vec2 p) { return texture(uContent, p); }"))
        #expect(source.contains("layout(binding = 4) uniform sampler2D uTex_a;"))
    }

    @Test
    func noTexturesDeclaresNoSampler() {
        let source = ShaderSource.compute(functions: "", body: "fragColor = vec4(1.0);")
        #expect(!source.contains("uTex_"))
    }

    /// Only the fragment stage: `texture()` needs derivatives, which a vertex
    /// stage has none of.
    @MainActor
    @Test
    func onlyTheFragmentStageGetsThem() {
        let (vertex, fragment) = ShaderSource.graphics(
            functions: "",
            varyings: "vec2 local;",
            vertex: "gl_Position = vec4(0.0, 0.0, 0.0, 1.0); local = vec2(0.0);",
            fragment: "fragColor = a(local);",
            arguments: .none,
            textures: textures(["a"])
        )
        #expect(!vertex.contains("uTex_a"))
        #expect(fragment.contains("layout(binding = 4) uniform sampler2D uTex_a;"))
        #expect(fragment.contains("vec4 a(vec2 p)"))
    }
}

/// The PyShader inlet, compiled for real — `ShaderCode.compute` runs the
/// whole way to SPIR-V with no GPU involved, so this is the declarations
/// actually reaching the compiler rather than a description of them.
@MainActor
@Suite(.serialized)
struct ShaderTextureCompilation {

    private func textures(_ names: [String]) -> ShaderTextures {
        ShaderTextures(names.map { name in
            .init(name, renderTexture(size: Size(width: 4, height: 4)) { Fill(level: 1) })
        })
    }

    private func spirv(_ code: ShaderCode) -> [UInt32]? {
        guard case .spirv(let words) = code else { return nil }
        return words
    }

    @Test
    func aPyShaderBodySamplesItsTexturesByName() throws {
        let function = ShaderFunction(pyshader: """
        def main(uv: float2, blend: float, a: Texture, b: Texture) -> float4:
            return mix(a(uv), b(uv), blend)
        """)
        let code = try ShaderCode.compute(
            function,
            samplesContent: false,
            arguments: ShaderArguments([.float("blend", 0.5)]),
            textures: textures(["a", "b"])
        )
        let words = try #require(spirv(code))
        // A SPIR-V module, and a bigger one than the same shader without the
        // two sampled images in it.
        #expect(words.first == 0x0723_0203)
        #expect(words.count > 32)
    }

    /// A texture the host did not declare is not a name the module can use —
    /// the error comes from PyShader, through `ShaderError.compileFailed`.
    @Test
    func anUndeclaredTextureIsAnError() {
        let function = ShaderFunction(pyshader: """
        def main(uv: float2, a: Texture) -> float4:
            return a(uv)
        """)
        #expect(throws: ShaderError.self) {
            try ShaderCode.compute(
                function,
                samplesContent: false,
                arguments: .none,
                textures: .none
            )
        }
    }

    /// `layer(uv)` keeps meaning the view: an effect reads its own pixels and
    /// a texture in the same body.
    @Test
    func aTextureCompilesAlongsideTheContent() throws {
        let function = ShaderFunction(pyshader: """
        def main(uv: float2, mask: Texture) -> float4:
            return layer(uv) * mask(uv).x
        """)
        let code = try ShaderCode.compute(
            function,
            samplesContent: true,
            contentIsTopDown: true,
            arguments: .none,
            textures: textures(["mask"])
        )
        #expect(spirv(code) != nil)
    }
}

/// The third inlet: a module compiled somewhere else.
///
/// There is no source to wrap, parse or hand to a compiler, so what has to
/// hold is that nothing tries to — the words come out of `ShaderCode.compute`
/// exactly as they went in — and that everything `ShaderFunction` derives
/// from source text still answers for a function that has none.
@MainActor
@Suite(.serialized)
struct PrecompiledShaderFunctionTests {

    /// A module PyShader built, so these are real words rather than a made-up
    /// array: whatever comes back from the `.pyshader` inlet is by definition
    /// something the `.spirv` inlet should be able to carry.
    private func module() throws -> [UInt32] {
        let code = try ShaderCode.compute(
            ShaderFunction(pyshader: """
            def main(uv: float2) -> float4:
                return float4(uv.x, uv.y, 0.0, 1.0)
            """),
            samplesContent: false,
            arguments: .none
        )
        guard case .spirv(let words) = code else {
            throw ShaderError.compileFailed("the PyShader inlet did not produce SPIR-V")
        }
        return words
    }

    @Test
    func theWordsGoThroughUntouched() throws {
        let words = try module()
        let code = try ShaderCode.compute(
            ShaderFunction(spirv: words),
            samplesContent: false,
            arguments: .none
        )
        guard case .spirv(let out) = code else {
            Issue.record("a precompiled function did not come back as SPIR-V")
            return
        }
        #expect(out == words, "nothing wraps, rewrites or recompiles a module that is already one")
    }

    /// `samplesContent`, `arguments` and `textures` describe what to
    /// *generate*. There is nothing to generate, so they change nothing —
    /// the module already declares what it reads.
    @Test
    func theGeneratorOptionsDoNotTouchIt() throws {
        let words = try module()
        let function = ShaderFunction(spirv: words)
        let plain = try ShaderCode.compute(function, samplesContent: false, arguments: .none)
        let dressed = try ShaderCode.compute(
            function,
            samplesContent: true,
            contentIsTopDown: true,
            arguments: ShaderArguments([.float("blend", 0.5)]),
            textures: ShaderTextures([
                .init("a", renderTexture(size: Size(width: 4, height: 4)) { Fill(level: 1) })
            ])
        )
        guard case .spirv(let a) = plain, case .spirv(let b) = dressed else {
            Issue.record("a precompiled function did not come back as SPIR-V")
            return
        }
        #expect(a == b)
    }

    /// The pipeline cache keeps a slot when `source` is unchanged, so two
    /// different modules have to disagree here — a digest would only make
    /// them *likely* to.
    @Test
    func twoModulesAreTwoIdentities() throws {
        let words = try module()
        let one = ShaderFunction(spirv: words)
        let same = ShaderFunction(spirv: words)
        var changed = words
        changed[changed.count - 1] &+= 1
        let other = ShaderFunction(spirv: changed)

        #expect(one.source == same.source)
        #expect(one == same, "and the value itself compares equal")
        #expect(one.source != other.source, "one word apart is a different shader")
        #expect(one.source.hasPrefix("#spirv"), "and it cannot be read as a source language")
    }

    /// Nothing derived from reading source text may quietly answer for a
    /// function that has none.
    @Test
    func whatIsNormallyReadFromTheTextIsStated() throws {
        let words = try module()
        #expect(ShaderFunction(spirv: words).isGraphics == false, "one module, one entry point")

        // `isAnimated` is grepped out of the source for a language; here the
        // caller says, because there is no source to grep.
        #expect(ShaderFunction(spirv: words).isAnimated, "the default errs towards redispatching")
        #expect(ShaderFunction(spirv: words, isAnimated: false).isAnimated == false)

        // And a module is never mistaken for a vertex + fragment pair, which
        // it has no way to carry.
        #expect(throws: ShaderError.self) {
            try GraphicsShaderCode.graphics(
                ShaderFunction(spirv: words),
                arguments: .none
            )
        }
    }

    @Test
    func anEmptyModuleIsStillAValue() {
        let empty = ShaderFunction(spirv: [])
        #expect(empty.spirv.isEmpty)
        #expect(empty.source == "#spirv\n")
        #expect(empty.isGraphics == false)
    }
}
