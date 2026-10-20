//
//  ShaderInput.swift
//  NucleantUI
//
import Observation

/// What a shader is handed from Swift: an object that packs its current
/// values into the shader's argument buffer.
///
/// Observable, so a change reaches the shader without going through the
/// view tree: whoever runs the shader packs the input inside
/// `withObservationTracking`, and the first change to anything `pack` read
/// has it packed and uploaded again. A data model can be one directly —
///
/// ```swift
/// @MainActor @Observable
/// final class Glow: ShaderInput {
///     var intensity: Float = 1
///     var tint = Float4(1, 0.5, 0, 1)
///
///     func pack(into bytes: inout [UInt8]) {
///         intensity.pack(into: &bytes)
///         tint.pack(into: &bytes)
///     }
/// }
/// ```
///
/// — or the values can be listed with `ShaderTupleArguments { … }`.
///
/// Main-actor: it is packed where frames are drawn, and a model it reads is
/// a main-actor model.
@MainActor
public protocol ShaderInput: Observable, AnyObject {
    /// Append the values, in the order and layout the shader's argument
    /// struct declares them.
    func pack(into bytes: inout [UInt8])
}
