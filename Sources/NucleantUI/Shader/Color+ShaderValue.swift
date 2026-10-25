//
//  Color+ShaderValue.swift
//  NucleantUI
//

/// A `vec4` of the color's red, green, blue and alpha, exactly as they were
/// given — nothing is resolved, converted or faded on the way. A
/// `Color.dynamic` packs its light components; a view that wants the one
/// its scheme shows resolves it first, with `resolved(for:)`.
extension Color: ShaderValue {
    public func pack(into bytes: inout [UInt8]) {
        Float4(Float(red), Float(green), Float(blue), Float(alpha)).pack(into: &bytes)
    }
}
