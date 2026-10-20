//
//  ShaderViewTests.swift
//  NucleantUITests
//
//  `Shader<Function: ShaderProtocol>`: what a view holds, and when two views
//  are the same view. The dispatch itself needs an engine, which this
//  target does not have — the demo's Shaders screen runs it.
//

import Testing
@testable import NucleantUI

@MainActor
struct ShaderViewOverModules {

    @Test
    func aModuleIsTakenAsItIs() {
        let view = Shader(SpirvFunction(spirv: [1, 2, 3]))
        #expect(view.function.spirv == [1, 2, 3])
        #expect(view.draw == ShaderDraw(vertices: 6, instances: 1))
    }

    /// A `ShaderFunction` is a module like any other: the view holds the
    /// function with the arguments and textures it was handed, and those are
    /// what it compiles for and packs as its input.
    @Test
    func aShaderFunctionCarriesWhatItWasHanded() {
        let function = ShaderFunction("fragColor = vec4(uv, 0.0, 1.0);")
        let view = Shader(function, arguments: [.float("gain", 2)])
        #expect(view.function.arguments == [.float("gain", 2)])
        #expect(view.function.samplesContent == false, "a generative view reads no view")
        #expect(Shader(function).function == function, "with nothing handed, the function as it is")
        #expect(Shader(source: "fragColor = vec4(1.0);").function.body == "fragColor = vec4(1.0);")
    }

    /// New argument values are another view, so the slot packs them again.
    @Test
    func newArgumentsAreAnotherView() {
        let function = ShaderFunction("fragColor = vec4(gain);")
        let one = Shader(function, arguments: [.float("gain", 1)])
        #expect(one._isEquivalent(to: Shader(function, arguments: [.float("gain", 1)])))
        #expect(!one._isEquivalent(to: Shader(function, arguments: [.float("gain", 2)])))
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

    /// `.shader(_:)` over a module: the same module reading the same input
    /// object is the same modifier, so the view under it is not rebuilt for
    /// a parent's rebuild; another module, input object or flag is another.
    @Test
    func aModuleEffectIsItsModuleAndItsInputObject() {
        let input = ShaderNoArguments()
        let words: [UInt32] = [1, 2, 3]
        func effect(_ words: [UInt32], _ input: ShaderNoArguments, isEnabled: Bool = true) -> some View {
            Color.red.shader(SpirvFunction(spirv: words, input: input), isEnabled: isEnabled)
        }
        let one = effect(words, input)
        #expect(one._isEquivalent(to: effect(words, input)))
        #expect(!one._isEquivalent(to: effect([1, 2, 4], input)))
        #expect(!one._isEquivalent(to: effect(words, ShaderNoArguments())))
        #expect(!one._isEquivalent(to: effect(words, input, isEnabled: false)))
    }

    /// The view under the effect keeps its input: a tap inside it lands.
    /// (With no window there is no slot to run the module in, and the view
    /// draws as it would without it.)
    @Test
    func aModuleEffectLeavesItsViewsInput() async {
        let log = Log()
        let harness = Harness(
            Color.red
                .frame(width: 60, height: 30)
                .onTapGesture { log("tapped") }
                .shader(SpirvFunction(spirv: []))
        )
        await harness.tap(Point(x: 100, y: 100))
        #expect(log.take() == ["tapped"])
    }
}
