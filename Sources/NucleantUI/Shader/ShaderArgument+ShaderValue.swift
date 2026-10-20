//
//  ShaderArgument+ShaderValue.swift
//  NucleantUI
//

/// The value alone, as the argument's own type packs it — the name is what
/// `ShaderFunction`'s wrapper declares, and is not part of the bytes.
extension ShaderArgument: ShaderValue {
    public func pack(into bytes: inout [UInt8]) {
        switch self {
        case .float(_, let value): value.pack(into: &bytes)
        case .float2(_, let value): value.pack(into: &bytes)
        case .float3(_, let value): value.pack(into: &bytes)
        case .float4(_, let value): value.pack(into: &bytes)
        case .color(_, let value): value.pack(into: &bytes)
        case .floatArray(_, let value): value.pack(into: &bytes)
        case .float2Array(_, let value): value.pack(into: &bytes)
        case .float3Array(_, let value): value.pack(into: &bytes)
        case .float4Array(_, let value): value.pack(into: &bytes)
        }
    }
}
