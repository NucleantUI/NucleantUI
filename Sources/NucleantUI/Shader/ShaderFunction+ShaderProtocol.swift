//
//  ShaderFunction+ShaderProtocol.swift
//  NucleantUI
//
import NucleantShader

/// `ShaderFunction` as the module it compiles to and the arguments it reads.
///
/// Its source is wrapped for what it was handed — the arguments' names and
/// kinds, the textures' names, the view under `.shader(_:)` — and compiled
/// to one compute module; the argument values are its input. From there it
/// runs as every other `ShaderProtocol` does.
extension ShaderFunction: ShaderProtocol {

    /// The compiled module — the words a precompiled function was made
    /// with. Compiled once per wrapped source: the compiler keeps what it
    /// compiled by source. Empty when it does not compile; the error is
    /// logged.
    public var spirv: [UInt32] {
        switch language {
        case .spirv:
            return precompiled?.words ?? []
        case .glsl:
            let source = ShaderSource.compute(
                functions: functions,
                body: body,
                samplesContent: samplesContent,
                arguments: arguments,
                textures: textureNames
            )
            guard let words = VKShaderCompiler.shared.tryCompileCompute(source) else {
                nucleantLogError(
                    "NucleantUI: ShaderFunction did not compile: "
                    + "\(VKShaderCompiler.shared.lastErrorMessage ?? "shaderc rejected the compute shader")\n"
                )
                return []
            }
            return words
        }
    }

    /// The arguments it was handed, packed as its wrapper reads them.
    public var input: ShaderArguments { ShaderArguments(arguments) }
}
