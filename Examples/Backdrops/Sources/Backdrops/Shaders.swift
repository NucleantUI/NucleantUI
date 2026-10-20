//
//  Shaders.swift
//  Backdrops
//
//  The SPIR-V the build made from `Shaders/*.py` (see `pyshader.toml`),
//  read from the app's resources.
//

import Foundation

/// The module PyShader's build plugin compiled `Shaders/<name>.py` into.
func shaderModule(named name: String) -> [UInt32] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "spv"),
          let data = try? Data(contentsOf: url)
    else {
        fatalError("Backdrops: \(name).spv is not among the app's resources — is it listed in pyshader.toml?")
    }
    return data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
}

let auroraModule = shaderModule(named: "aurora")
