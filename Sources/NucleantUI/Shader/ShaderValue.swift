//
//  ShaderInputArgument.swift
//  NucleantUI
//
import Foundation

public protocol ShaderValue {
    func pack(into data: inout Data) // not sure if we should rely on Data or [UInt8]
    func pack(into bytes: inout [UInt8])
}

extension ShaderValue {
    public static var memorySize: Int { MemoryLayout<Self>.size }
    public static var memoryStride: Int { MemoryLayout<Self>.stride }
    
    public func pack(into data: inout Data) {
        withUnsafeBytes(of: self) { raw in
            data.append(contentsOf: raw)
        }
    }
    
    public func pack(into bytes: inout [UInt8]) {
        withUnsafeBytes(of: self) { raw in
            bytes.append(contentsOf: raw)
        }
    }
}
