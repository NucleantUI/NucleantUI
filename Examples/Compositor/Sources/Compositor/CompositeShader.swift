//
//  CompositeShader.swift
//  Compositor
//
//  One shader for the whole stack, written out from it.
//
//  Each visible layer is a named texture — `l0` at the bottom — and the body
//  samples them in order, folding each into the colour so far with its blend
//  mode. Nothing is drawn more than once and nothing is read back to the CPU:
//  the layers' textures are already on the GPU, and the composite is one
//  dispatch over them.
//
//  What goes where matters, and is the reason this is generated rather than
//  one fixed shader with a mode uniform:
//
//  * The *stack* — how many layers, in what order, with which blend — is the
//    source, compiled while the app runs by `PyShaderFunction`. Changing any
//    of it writes a new shader and a new module (a stack seen before is
//    compiled once and kept).
//  * The *mix* values are the shader's input: a `Mix` class with one field
//    per layer, packed from the layers' `mix` by a builder block. Dragging a
//    slider changes the layer, the shader reads it through observation and
//    uploads a few bytes; nothing is rebuilt or recompiled.
//  * The *pixels* of a layer are neither. Redrawing a layer writes into the
//    image the shader is already bound to, and the composite picks it up on
//    the next frame.
//

import NucleantUI
import NucleantUI_PyShader

/// The generated shader for one stack, with everything the view needs to
/// hand it over.
@MainActor
struct CompositeShader {

    /// Its input, the mix values, read when it is packed.
    let function: PyShaderFunction<ShaderTupleArguments<[Float]>>
    let textures: [ShaderTextureInput]
    /// The source, for the panel that shows it — this is an app about
    /// generating a shader, so it shows the shader it generated.
    let source: String

    init(stack: [CompositorLayer]) {
        let source = Self.source(for: stack)
        self.source = source
        let names = stack.enumerated().map { index, layer in layer.samplerName(at: index) }
        self.function = PyShaderFunction(source, textures: names, isAnimated: false) {
            stack.map { Float($0.mix) }
        }
        self.textures = zip(names, stack).map { name, layer in
            ShaderTextureInput(name, layer.texture)
        }
    }

    /// `def main(uv, amount, l0, l1, …)`, one fold per layer.
    ///
    /// `amount.a0` is the bottom layer's mix — `amount` the `Mix` input, one
    /// float per layer in stack order, as the Swift side packs it — and
    /// `l0(uv)` samples its texture, by the names the Swift side binds them
    /// under, so the two agree by construction.
    static func source(for stack: [CompositorLayer]) -> String {
        guard !stack.isEmpty else {
            return """
            def main(uv: float2) -> float4:
                return float4(0.0, 0.0, 0.0, 1.0)
            """
        }
        var lines = ["class Mix:"] + stack.indices.map { "    a\($0): float" } + ["", ""]
        let parameters = ["uv: float2", "amount: Mix"]
            + stack.indices.map { "l\($0): Texture" }
        lines.append("def main(\(parameters.joined(separator: ", "))) -> float4:")
        for (index, layer) in stack.enumerated() {
            let s = "s\(index)", a = "a\(index)", c = "c\(index)"
            lines.append("    \(s) = l\(index)(uv)")
            // The layer's own alpha times its mix: a transparent part of a
            // layer lets the stack below it through whatever the slider says.
            lines.append("    \(a) = \(s).w * amount.a\(index)")
            if index == 0 {
                // The bottom layer composites over black, so its blend mode
                // has nothing to blend with.
                lines.append("    \(c) = \(s).xyz * \(a)")
            } else {
                lines.append("    \(c) = \(fold(layer.blend, under: "c\(index - 1)", layer: "\(s).xyz", alpha: a))")
            }
        }
        lines.append("    return float4(c\(stack.count - 1), 1.0)")
        return lines.joined(separator: "\n")
    }

    /// One blend, as an expression over the colour so far (`under`), the
    /// layer's colour and its effective alpha.
    ///
    /// Each is written so that `alpha == 0` leaves `under` exactly as it was:
    /// a layer at zero mix costs a sample and changes nothing, which is what
    /// makes the sliders feel like layer opacity.
    private static func fold(_ blend: LayerBlend, under: String, layer: String, alpha: String) -> String {
        let one = "float3(1.0)"
        switch blend {
        case .normal:
            return "\(under) * (1.0 - \(alpha)) + \(layer) * \(alpha)"
        case .add:
            return "\(under) + \(layer) * \(alpha)"
        case .screen:
            return "\(one) - (\(one) - \(under)) * (\(one) - \(layer) * \(alpha))"
        case .multiply:
            return "\(under) * (1.0 - \(alpha)) + \(under) * \(layer) * \(alpha)"
        case .difference:
            return "\(under) * (1.0 - \(alpha)) + abs(\(under) - \(layer)) * \(alpha)"
        }
    }
}
