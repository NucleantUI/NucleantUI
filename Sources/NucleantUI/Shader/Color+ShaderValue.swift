//
//  Color+ShaderValue.swift
//  NucleantUI
//

/// A `vec4` of red, green, blue and alpha.
///
/// The light components: packing has no environment to resolve a dynamic
/// color in, so a color that differs in dark mode is resolved by whoever
/// holds the scheme — `color.resolved(for: scheme)` — before it is packed.
extension Color: ShaderValue {
    public func pack(into bytes: inout [UInt8]) {
        Float4(Float(red), Float(green), Float(blue), Float(alpha)).pack(into: &bytes)
    }
}
