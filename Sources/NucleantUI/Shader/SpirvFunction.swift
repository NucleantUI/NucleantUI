//
//  SpirvFunction.swift
//  NucleantUI
//

/// A SPIR-V module, used as it is — for code compiled by anything other than
/// this framework: a `.spv` from the PyShader build plugin, glslang, a node
/// graph.
///
/// ```swift
/// let glow = SpirvFunction(spirv: words) {
///     model.intensity
///     model.tint
/// }
/// ```
public struct SpirvFunction<Input: ShaderInput>: ShaderProtocol {
    public let spirv: [UInt32]
    public let input: Input
    public let isAnimated: Bool

    public init(spirv: [UInt32], input: Input, isAnimated: Bool = true) {
        self.spirv = spirv
        self.input = input
        self.isAnimated = isAnimated
    }
}

extension SpirvFunction where Input == ShaderNoArguments {
    /// A module that takes no input.
    public init(spirv: [UInt32], isAnimated: Bool = true) {
        self.init(spirv: spirv, input: ShaderNoArguments(), isAnimated: isAnimated)
    }
}

extension SpirvFunction {
    /// A module whose input is the values `arguments` lists, in order.
    @MainActor
    public init<each Value: ShaderValue>(
        spirv: [UInt32],
        isAnimated: Bool = true,
        @ShaderArgumentsBuilder arguments: @escaping @MainActor () -> (repeat each Value)
    ) where Input == ShaderTupleArguments<repeat each Value> {
        self.init(spirv: spirv, input: ShaderTupleArguments(arguments), isAnimated: isAnimated)
    }
}

/// The same module reading the same input object. Which values the input
/// holds is not part of it: those reach the shader through observation.
extension SpirvFunction: Equatable {
    public static func == (lhs: SpirvFunction, rhs: SpirvFunction) -> Bool {
        lhs.input === rhs.input && lhs.isAnimated == rhs.isAnimated && lhs.spirv == rhs.spirv
    }
}
