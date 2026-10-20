//
//  ShaderModules.swift
//  NucleantUIDemo
//
//  The demo's PyShader shaders, as the SPIR-V they were compiled to —
//  `Shaders/<name>.py` beside `Shaders/<name>.spv`, the `pyshaderc` command
//  in each `.py`'s header.
//

import Foundation

/// `Shaders/<name>.spv`, from the demo's resources.
func shaderModule(named name: String) -> [UInt32] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "spv", subdirectory: "Shaders"),
          let data = try? Data(contentsOf: url)
    else {
        fatalError("NucleantUIDemo: Shaders/\(name).spv is not among the demo's resources")
    }
    return data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
}
