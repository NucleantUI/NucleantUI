//
//  Float4.swift
//  NucleantUI
//
//  Created by CodeBuilder on 20/10/2026.
//


public struct Float4: Hashable, Sendable {
    public var v1: Float
    public var v2: Float
    public var v3: Float
    public var v4: Float

    public init(_ v1: Float, _ v2: Float, _ v3: Float, _ v4: Float) {
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.v4 = v4
    }
    
    public init<F: BinaryFloatingPoint>(_ v1: F, _ v2: F, _ v3: F, _ v4: F) {
        self.v1 = .init(v1)
        self.v2 = .init(v2)
        self.v3 = .init(v3)
        self.v4 = .init(v4)
    }
}