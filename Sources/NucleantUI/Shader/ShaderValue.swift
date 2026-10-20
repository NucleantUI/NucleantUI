//
//  ShaderValue.swift
//  NucleantUI
//

/// A value a shader reads from its argument buffer, written as the bytes the
/// GPU reads.
///
/// Bytes, not floats: everything ends up as bytes in a `VkBuffer` anyway, so
/// a value appends its own straight into the buffer's image rather than
/// passing through a `[Float]` first, and a new kind of value is a new
/// conformance rather than a new case somewhere. `[UInt8]` rather than
/// `Data`, so nothing here needs Foundation and the bytes go to the C side
/// as they are.
///
/// The default copies the value's own memory, after padding `bytes` to its
/// alignment — right for a scalar and for a struct of them. A type whose GPU
/// layout differs from its Swift one overrides `pack` (`Float3` is 12 bytes
/// in Swift and 16-aligned in a std430 buffer), and a struct mirroring a
/// shader's struct packs field by field so each field aligns itself.
public protocol ShaderValue {
    /// Append this value's bytes to `bytes`, padding it first to wherever
    /// the value's alignment puts it — `bytes.count` is the offset in the
    /// buffer the value lands at.
    func pack(into bytes: inout [UInt8])
}

extension ShaderValue {
    public static var memorySize: Int { MemoryLayout<Self>.size }
    public static var memoryStride: Int { MemoryLayout<Self>.stride }

    public func pack(into bytes: inout [UInt8]) {
        Self.align(&bytes, to: MemoryLayout<Self>.alignment)
        withUnsafeBytes(of: self) { raw in
            bytes.append(contentsOf: raw)
        }
    }

    /// Zero bytes until `bytes.count` is a multiple of `alignment`.
    static func align(_ bytes: inout [UInt8], to alignment: Int) {
        let remainder = bytes.count % alignment
        guard remainder != 0 else { return }
        bytes.append(contentsOf: repeatElement(0, count: alignment - remainder))
    }
}

extension Float: ShaderValue {}
extension Int32: ShaderValue {}
extension UInt32: ShaderValue {}

/// A std430 array: each element where its own alignment puts it, so a
/// `[Float3]` has the 16-byte stride a `vec3[]` reads with.
extension Array: ShaderValue where Element: ShaderValue {
    public func pack(into bytes: inout [UInt8]) {
        for element in self {
            element.pack(into: &bytes)
        }
    }
}
