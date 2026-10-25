//
//  Color+ShaderValue.swift
//  NucleantUI
//

/// A `vec4` of the color's red, green, blue and alpha, exactly as they were
/// given — nothing is converted or faded on the way.
extension Color: ShaderValue {
    /// 16-aligned, as std430 places a `vec4`, and the color's own 16 bytes.
    public func pack(into bytes: inout [UInt8]) {
        Self.align(&bytes, to: 16)
        withUnsafeBytes(of: self) { bytes.append(contentsOf: $0) }
    }
}
