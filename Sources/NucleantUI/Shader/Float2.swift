//
//  Float2.swift
//  NucleantUI
//

/// Two, three and four floats, laid out as the GPU reads them.
///
/// Plain `Float` fields and nothing else, so an array of them is the byte
/// image of a `vec2[]`/`vec3[]`/`vec4[]` and is copied into the argument
/// buffer whole rather than a component at a time.
public struct Float2: Hashable, Sendable {
    public var v1: Float
    public var v2: Float

    public init(_ v1: Float, _ v2: Float) {
        self.v1 = v1
        self.v2 = v2
    }

    public init<F: BinaryFloatingPoint>(_ v1: F, _ v2: F) {
        self.v1 = .init(v1)
        self.v2 = .init(v2)
    }
}

extension Float2: ShaderValue {
    /// 8-aligned, as std430 places a `vec2`.
    public func pack(into bytes: inout [UInt8]) {
        Self.align(&bytes, to: 8)
        withUnsafeBytes(of: self) { bytes.append(contentsOf: $0) }
    }
}
