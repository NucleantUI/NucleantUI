//
//  ShaderViewTests.swift
//  NucleantUITests
//
//  `Shader` over any `ShaderProtocol`: which path a view takes, and when two
//  views are the same view. The dispatch itself needs an engine, which this
//  target does not have — the demo's Shaders screen runs it.
//

import Testing
@testable import NucleantUI

@MainActor
struct ShaderViewOverModules {

    @Test
    func aModuleIsTakenAsItIs() {
        let view = Shader(SpirvFunction(spirv: [1, 2, 3]))
        #expect(view.sourceFunction == nil)
        #expect(view.arguments.isEmpty)
        #expect(view.draw == ShaderDraw(vertices: 6, instances: 1))
    }

    /// The `ShaderFunction` inits keep compiling the source for their
    /// arguments, whatever the generic path could do with the function.
    @Test
    func aShaderFunctionKeepsItsOwnPath() {
        let function = ShaderFunction("fragColor = vec4(uv, 0.0, 1.0);")
        let view = Shader(function, arguments: [.float("gain", 2)])
        #expect(view.sourceFunction == function)
        #expect(view.arguments == [.float("gain", 2)])
        #expect(Shader(function).sourceFunction == function, "with no arguments too")
        #expect(Shader(source: "fragColor = vec4(1.0);").sourceFunction != nil)
    }

    @Test
    func verticesAndInstancesAreClamped() {
        let view = Shader(SpirvFunction(spirv: []), vertices: -1, instances: 4)
        #expect(view.draw == ShaderDraw(vertices: 0, instances: 4))
    }

    /// The same module reading the same input is the same view, so a parent
    /// rebuilding does not rebuild it; another input object is another view.
    @Test
    func aViewIsItsModuleAndItsInputObject() {
        let input = ShaderNoArguments()
        let words: [UInt32] = [1, 2, 3]
        let one = Shader(SpirvFunction(spirv: words, input: input))
        #expect(one._isEquivalent(to: Shader(SpirvFunction(spirv: words, input: input))))
        #expect(!one._isEquivalent(to: Shader(SpirvFunction(spirv: words, input: ShaderNoArguments()))))
        #expect(!one._isEquivalent(to: Shader(SpirvFunction(spirv: [1, 2, 4], input: input))))
    }
}
