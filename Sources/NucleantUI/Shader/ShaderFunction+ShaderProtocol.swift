//
//  ShaderFunction+ShaderProtocol.swift
//  NucleantUI
//
import NucleantShader

/// `ShaderFunction` as a plain module: compiled for a generative `Shader`
/// with no `ShaderArgument`s, no textures and no content to sample.
///
/// Its arguments, textures and `.shader(_:)` content each change what its
/// source compiles to, so used with those it keeps going through its own
/// `Shader(_:arguments:textures:)` and `.shader(_:)`. This is the module for
/// anywhere that takes any `ShaderProtocol`.
extension ShaderFunction: ShaderProtocol {

    /// Compiled on every read — hold the result rather than reading it again.
    /// Empty when it does not compile (the error is logged), and for a GLSL
    /// vertex + fragment pair, which is two modules rather than one.
    public var spirv: [UInt32] {
        do {
            switch try ShaderCode.compute(self, samplesContent: false, arguments: .none) {
            case .spirv(let words):
                return words
            case .glsl(let source):
                guard glslVertexStage == nil else {
                    nucleantLogError("NucleantUI: a GLSL vertex + fragment ShaderFunction is two modules, not one\n")
                    return []
                }
                guard let words = VKShaderCompiler.shared.tryCompileCompute(source) else {
                    throw ShaderError.compileFailed(VKShaderCompiler.shared.lastErrorMessage ?? "shaderc rejected the compute shader")
                }
                return words
            }
        } catch {
            nucleantLogError("NucleantUI: ShaderFunction did not compile: \(error)\n")
            return []
        }
    }

    public var input: ShaderNoArguments { ShaderNoArguments() }
}
