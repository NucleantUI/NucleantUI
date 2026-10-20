//
//  Fixtures.swift
//  NucleantUITests
//
//  SPIR-V modules for the tests, compiled once from the `.py` beside each
//  in `Fixtures/` (the command is in its header) — real modules, with no
//  compiler in the framework or its tests.
//

import Foundation

enum Fixture {
    /// `def main`: one `GLCompute` entry point, `main`.
    static let compute = words("compute")
    /// `def vertex` + `def fragment`: `vertex_main` and `fragment_main`.
    static let graphics = words("graphics")

    private static func words(_ name: String) -> [UInt32] {
        let url = Bundle.module.url(forResource: name, withExtension: "spv", subdirectory: "Fixtures")!
        let data = try! Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }
}
