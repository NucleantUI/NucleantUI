//
//  ShaderArgumentsBuilder.swift
//  NucleantUI
//

/// Lists a shader's values one per line, in buffer order — what
/// `ShaderTupleArguments` is built from.
///
/// ```swift
/// ShaderTupleArguments {
///     30.0 as Float          // a constant
///     model.color            // a property of an @Observable model
///     model.level            // an ObservableValue<Float>, say
/// }
/// ```
///
/// The block is a tuple of the values, as `TupleView` is of views: each keeps
/// its own type, so each packs itself.
@resultBuilder
public struct ShaderArgumentsBuilder {
    public static func buildExpression<Value: ShaderValue>(_ value: Value) -> Value {
        value
    }

    public static func buildBlock<each Value: ShaderValue>(_ values: repeat each Value) -> (repeat each Value) {
        (repeat each values)
    }
}
