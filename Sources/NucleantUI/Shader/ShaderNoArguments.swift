//
//  ShaderNoArguments.swift
//  NucleantUI
//
import Observation

/// The input of a shader that takes none: packs nothing, never changes.
public final class ShaderNoArguments: ShaderInput {
    public init() {}

    public func pack(into bytes: inout [UInt8]) {}
}
