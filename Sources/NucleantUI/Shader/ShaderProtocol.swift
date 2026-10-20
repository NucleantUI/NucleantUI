//
//  ShaderProtocol.swift
//  NucleantUI
//


/*
 instead of rely on one ShaderFunction todo all kinds of cases
 Shaders in NucleantUI should be 100% Spirv Bytecode nuetral
 it shouldnt care if glgs, pyshader or any of that..
 
 also means we should make a
 NucleantUI_PyShader package/repo
 and there we can introduce PyShaderFunction which conforms to ShaderProtocol
 
 
*/

public protocol ShaderProtocol {
    var spirv: [UInt32] { get }
}
