//
//  ShaderValueTests.swift
//  NucleantUITests
//
//  What a `ShaderValue` writes into an argument buffer: its bytes, at the
//  offset a std430 struct puts it.
//

import Testing
@testable import NucleantUI

struct ShaderValuePacking {

    private func bytes(_ pack: (inout [UInt8]) -> Void) -> [UInt8] {
        var bytes: [UInt8] = []
        pack(&bytes)
        return bytes
    }

    private func floats(_ bytes: [UInt8]) -> [Float] {
        bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    @Test
    func aScalarIsItsOwnBytes() {
        #expect(bytes { Float(1.5).pack(into: &$0) } == withUnsafeBytes(of: Float(1.5)) { Array($0) })
        #expect(bytes { Int32(-2).pack(into: &$0) }.count == 4)
        #expect(bytes { UInt32(7).pack(into: &$0) }.count == 4)
    }

    /// std430: `float a; vec2 b;` puts `b` at 8, not 4.
    @Test
    func aFloat2IsEightAligned() {
        let packed = bytes {
            Float(1).pack(into: &$0)
            Float2(2, 3).pack(into: &$0)
        }
        #expect(packed.count == 16)
        #expect(floats(packed) == [1, 0, 2, 3])
    }

    /// std430: `float a; vec3 b; float c;` — `b` at 16, and `c` fills the
    /// fourth slot behind it at 28.
    @Test
    func aFloat3IsSixteenAlignedAndTwelveLong() {
        let packed = bytes {
            Float(1).pack(into: &$0)
            Float3(2, 3, 4).pack(into: &$0)
            Float(5).pack(into: &$0)
        }
        #expect(packed.count == 32)
        #expect(floats(packed) == [1, 0, 0, 0, 2, 3, 4, 5])
    }

    @Test
    func aFloat4IsSixteenAligned() {
        let packed = bytes {
            Float(1).pack(into: &$0)
            Float4(2, 3, 4, 5).pack(into: &$0)
        }
        #expect(floats(packed) == [1, 0, 0, 0, 2, 3, 4, 5])
    }

    /// A `vec3[]` has a 16-byte stride.
    @Test
    func anArrayPacksEachElementAtItsAlignment() {
        #expect(floats(bytes { [Float3(1, 2, 3), Float3(4, 5, 6)].pack(into: &$0) }) == [1, 2, 3, 0, 4, 5, 6])
        #expect(floats(bytes { [Float(1), 2, 3].pack(into: &$0) }) == [1, 2, 3])
    }

    @Test
    func aColorIsAVec4OfItsLightComponents() {
        let color = Color.dynamic(light: Color(red: 1, green: 0.5, blue: 0, opacity: 0.25), dark: .black)
        #expect(floats(bytes { color.pack(into: &$0) }) == [1, 0.5, 0, 0.25])
    }

    /// The value alone — the name is not part of the bytes.
    @Test
    func aShaderArgumentPacksItsValue() {
        #expect(floats(bytes { ShaderArgument.float4("tint", Float4(1, 2, 3, 4)).pack(into: &$0) }) == [1, 2, 3, 4])
        #expect(floats(bytes { ShaderArgument.floatArray("xs", [1, 2]).pack(into: &$0) }) == [1, 2])
    }
}
