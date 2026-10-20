//
//  ShaderProtocol.swift
//  NucleantUI
//

/// A shader as NucleantUI runs it: a SPIR-V module and the input it reads.
///
/// Nothing here knows what the module was written in — GLSL, PyShader, a
/// node graph, a `.spv` a build plugin produced. The host reads what it needs
/// from the module itself: an `OpEntryPoint` for `GLCompute` is dispatched
/// over every pixel, a `Vertex` + `Fragment` pair is drawn as geometry.
///
/// The module binds what NucleantUI's compute and graphics pipelines bind:
/// the storage image written one pixel per invocation at binding 0 (compute
/// only), the `Uniforms` block — clock, resolution, pointer — at 1, and the
/// input's bytes as a storage buffer at binding 3, laid out as the module's
/// own struct declares them (std430).
public protocol ShaderProtocol {
    associatedtype Input: ShaderInput

    /// The module, as `vkCreateShaderModule` takes it.
    var spirv: [UInt32] { get }

    /// What the module reads from binding 3. A change to anything it packs
    /// is uploaded and redrawn without the view tree being involved.
    var input: Input { get }

    /// Whether the module reads the clock or the pointer, and so draws
    /// again every frame rather than only when its input changes.
    var isAnimated: Bool { get }
}

extension ShaderProtocol {
    /// Erring towards redrawing only costs dispatches; the other way round
    /// would freeze a shader that does move.
    public var isAnimated: Bool { true }
}
