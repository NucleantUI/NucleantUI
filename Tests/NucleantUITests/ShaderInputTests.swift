//
//  ShaderInputTests.swift
//  NucleantUITests
//
//  `ShaderTupleArguments`: the values a builder block lists, packed in
//  order, and observed through whatever the block reads.
//

import Observation
import Testing
@testable import NucleantUI

@Observable
private final class Model {
    var level: Float = 1
    var tint = Float4(1, 0, 0, 1)
}

/// An observable class that is itself a value, packing what it holds.
@Observable
private final class ObservedLevel: ShaderValue {
    var value: Float = 0.5

    func pack(into bytes: inout [UInt8]) {
        value.pack(into: &bytes)
    }
}

/// A model that is its own input.
@Observable
private final class Glow: ShaderInput {
    var intensity: Float = 1
    func pack(into bytes: inout [UInt8]) { intensity.pack(into: &bytes) }
}

/// Set from a change handler — a class so the `@Sendable` handler can
/// reach it.
private final class Flag: @unchecked Sendable {
    var isSet = false
}

@MainActor
struct ShaderInputPacking {

    private func floats(_ input: some ShaderInput) -> [Float] {
        var bytes: [UInt8] = []
        input.pack(into: &bytes)
        return bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Packs `input` under observation, returning what turns true on the
    /// first change to anything it read.
    private func track(_ input: some ShaderInput) -> Flag {
        let flag = Flag()
        withObservationTracking {
            var bytes: [UInt8] = []
            input.pack(into: &bytes)
        } onChange: {
            flag.isSet = true
        }
        return flag
    }

    @Test
    func noArgumentsPackNothing() {
        #expect(floats(ShaderNoArguments()).isEmpty)
        #expect(floats(ShaderTupleArguments {}).isEmpty)
    }

    @Test
    func oneValue() {
        #expect(floats(ShaderTupleArguments { Float(3) }) == [3])
    }

    /// In order, each at its own alignment: the `vec4` lands at 16.
    @Test
    func valuesPackInOrderAtTheirAlignment() {
        let input = ShaderTupleArguments {
            Float(30)
            Float4(1, 2, 3, 4)
            [Float(5), 6]
        }
        #expect(floats(input) == [30, 0, 0, 0, 1, 2, 3, 4, 5, 6])
    }

    /// The block runs again on every pack, so a pack is of the values as
    /// they are now.
    @Test
    func packReadsTheCurrentValues() {
        let model = Model()
        let input = ShaderTupleArguments {
            model.level
            model.tint
        }
        #expect(floats(input) == [1, 0, 0, 0, 1, 0, 0, 1])
        model.level = 2
        model.tint = Float4(0, 1, 0, 1)
        #expect(floats(input) == [2, 0, 0, 0, 0, 1, 0, 1])
    }

    @Test
    func aChangeToAPropertyTheBlockReadIsAChange() {
        let model = Model()
        let input = ShaderTupleArguments { model.level }
        let changed = track(input)
        model.tint = Float4(0, 0, 0, 0)
        #expect(!changed.isSet, "the block never read tint")
        model.level = 4
        #expect(changed.isSet)
    }

    @Test
    func anObservableValueIsObservedThroughItsPack() {
        let level = ObservedLevel()
        let input = ShaderTupleArguments {
            Float(1)
            level
        }
        let changed = track(input)
        level.value = 0.75
        #expect(changed.isSet)
        #expect(floats(input) == [1, 0.75])
    }

    /// A model that is its own input.
    @Test
    func aModelCanBeTheInput() {
        let glow = Glow()
        let changed = track(glow)
        glow.intensity = 2
        #expect(changed.isSet)
        #expect(floats(glow) == [2])
    }
}
