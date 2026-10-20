//
//  ShaderTupleArguments.swift
//  NucleantUI
//
import Observation

/// A shader input listed value by value — none, one or any number of them.
///
/// ```swift
/// let input = ShaderTupleArguments {
///     Float(30)
///     model.tint
///     model.level
/// }
/// ```
///
/// It keeps the block, not the values: `pack` runs it again, so it always
/// packs what the values are now, and whatever observable state the block
/// reads — `model.tint` on an `@Observable` model, a value that is itself an
/// observable class — is read inside the shader's observation scope. A change
/// to any of it is a change to this input, with nothing to forward.
public final class ShaderTupleArguments<each Value: ShaderValue>: ShaderInput {
    let values: () -> (repeat each Value)

    public init(@ShaderArgumentsBuilder _ values: @escaping () -> (repeat each Value)) {
        self.values = values
    }

    public func pack(into bytes: inout [UInt8]) {
        let current = values()
        for value in repeat each current {
            value.pack(into: &bytes)
        }
    }
}
