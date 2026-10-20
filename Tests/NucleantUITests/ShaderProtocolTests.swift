//
//  ShaderProtocolTests.swift
//  NucleantUITests
//
//  A module as `ShaderProtocol` hands it over: the stage read from its own
//  entry points, `SpirvFunction`'s identity, and `ShaderFunction` as one.
//

import Observation
import Testing
@testable import NucleantUI

@Observable
private final class Tint {
    var red: Float = 1
}

@MainActor
struct ShaderProtocolModules {

    @Test
    func aComputeModuleIsDispatched() {
        let stages = SpirvEntryPoints(Fixture.compute)
        #expect(stages.compute == "main")
        #expect(stages.vertex == nil && stages.fragment == nil)
        #expect(!stages.isGraphics)
    }

    /// Both stages in one module, each under its own name — nothing has to
    /// grep the source for a `def vertex`.
    @Test
    func aVertexAndFragmentModuleIsDrawn() {
        let stages = SpirvEntryPoints(Fixture.graphics)
        #expect(stages.isGraphics)
        #expect(stages.vertex == "vertex_main")
        #expect(stages.fragment == "fragment_main")
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
    func aSpirvFunctionIsItsWordsAndItsInputObject() {
        let words = Fixture.compute
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
