//
//  Float3.swift
//  NucleantUI
//

public struct Float3: Hashable, Sendable {
    public var v1: Float
    public var v2: Float
    public var v3: Float

    public init(_ v1: Float, _ v2: Float, _ v3: Float) {
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
    }

    public init<F: BinaryFloatingPoint>(_ v1: F, _ v2: F, _ v3: F) {
        self.v1 = .init(v1)
        self.v2 = .init(v2)
        self.v3 = .init(v3)
    }
}

extension Float3: ShaderValue {
    /// 16-aligned and 12 bytes long, as std430 places a `vec3`: a `float`
    /// after it fills the fourth slot, another `vec3` starts on the next 16.
    public func pack(into bytes: inout [UInt8]) {
        Self.align(&bytes, to: 16)
        withUnsafeBytes(of: self) { bytes.append(contentsOf: $0) }
    }
}
