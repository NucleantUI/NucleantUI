//
//  ShaderProtocolTests.swift
//  NucleantUITests
//
//  A module as `ShaderProtocol` hands it over: the stage read from its own
//  entry points, `SpirvFunction`'s identity, and `ShaderFunction` as one.
//

import Observation
import PyShader
import Testing
@testable import NucleantUI

@Observable
private final class Tint {
    var red: Float = 1
}

@MainActor
struct ShaderProtocolModules {

    private let compute = """
        def main(uv: float2) -> float4:
            return float4(uv.x, uv.y, 0.0, 1.0)
        """

    private let graphics = """
        class V:
            position: float4
            uv: float2

        def vertex(vertex_index: int) -> V:
            corner = float2(float(vertex_index & 1), float(vertex_index >> 1))
            return V(position=float4(corner * 2.0 - 1.0, 0.0, 1.0), uv=corner)

        def fragment(uv: float2) -> float4:
            return float4(uv.x, uv.y, 0.0, 1.0)
        """

    @Test
    func aComputeModuleIsDispatched() throws {
        let words = try PyShader.compile(compute, target: .nucleantUI).spirv
        let stages = SpirvEntryPoints(words)
        #expect(stages.compute == "main")
        #expect(stages.vertex == nil && stages.fragment == nil)
        #expect(!stages.isGraphics)
    }

    /// Both stages in one module, each under its own name — nothing has to
    /// grep the source for a `def vertex`.
    @Test
    func aVertexAndFragmentModuleIsDrawn() throws {
        let compiled = try PyShader.compile(graphics, target: .nucleantUIGraphics)
        let stages = SpirvEntryPoints(compiled.spirv)
        #expect(stages.isGraphics)
        #expect(stages.vertex == compiled.vertexEntryPoint)
        #expect(stages.fragment == compiled.entryPoint)
        #expect(stages.compute == nil)
    }

    @Test
    func wordsThatAreNotAModuleHaveNoStage() {
        #expect(SpirvEntryPoints([]) == SpirvEntryPoints([1, 2, 3, 4, 5, 6]))
        #expect(SpirvEntryPoints([]).compute == nil)
    }

    /// Same words and the same input object; the values the input holds
    /// are not part of it.
    @Test
    func aSpirvFunctionIsItsWordsAndItsInputObject() throws {
        let words = try PyShader.compile(compute, target: .nucleantUI).spirv
        let input = ShaderNoArguments()
        #expect(SpirvFunction(spirv: words, input: input) == SpirvFunction(spirv: words, input: input))
        #expect(SpirvFunction(spirv: words, input: input) != SpirvFunction(spirv: words, input: ShaderNoArguments()))
        #expect(SpirvFunction(spirv: words, input: input) != SpirvFunction(spirv: words, input: input, isAnimated: false))
        #expect(SpirvFunction(spirv: words, input: input) != SpirvFunction(spirv: words.dropLast() + [0], input: input))
    }

    @Test
    func aSpirvFunctionTakesItsArgumentsFromABuilder() {
        let tint = Tint()
        let function = SpirvFunction(spirv: []) {
            tint.red
            Float4(0, 1, 0, 1)
        }
        var bytes: [UInt8] = []
        function.input.pack(into: &bytes)
        #expect(bytes.count == 32)
        tint.red = 0.5
        bytes = []
        function.input.pack(into: &bytes)
        #expect(bytes.withUnsafeBytes { $0.load(as: Float.self) } == 0.5)
    }

    /// The same module the plain `Shader` path compiles it to.
    @Test
    func aPyShaderFunctionIsItsCompiledModule() throws {
        let function = ShaderFunction(pyshader: compute)
        let words = function.spirv
        #expect(words == (try PyShader.compile(compute, target: .nucleantUI).spirv))
        #expect(SpirvEntryPoints(words).compute == "main")
    }

    @Test
    func aGLSLFunctionIsCompiledToOneComputeModule() {
        let words = ShaderFunction("fragColor = vec4(uv, 0.0, 1.0);").spirv
        #expect(!words.isEmpty)
        #expect(SpirvEntryPoints(words).compute == "main")
    }

    /// Two GLSL stages are two modules, which one `[UInt32]` cannot hold.
    @Test
    func aGLSLPairIsNotOneModule() {
        let pair = ShaderFunction(vertex: "gl_Position = vec4(0.0);", fragment: "fragColor = vec4(1.0);")
        #expect(pair.spirv.isEmpty)
    }

    @Test
    func aStaticFunctionSaysSo() {
        #expect(ShaderFunction("fragColor = vec4(1.0);").isAnimated == false)
        #expect(ShaderFunction("fragColor = vec4(sin(time));").isAnimated)
        #expect(SpirvFunction(spirv: []).isAnimated)
    }
}
