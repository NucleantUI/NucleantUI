//
//  ShaderRenderTextureTests.swift
//  NucleantUITests
//
//  A shader rendered into a `RenderTexture`, and watched for changes to its
//  input. The dispatch and the copy need an engine, which this target does
//  not have — Backdrops' preset thumbnails and its "Now" still run them.
//  What is covered here is what decides them: what a request carries, what
//  replaces it, and when a watched shader calls back.
//

import Observation
import Testing
@testable import NucleantUI

@MainActor @Observable
private final class Tint: ShaderInput {
    var level: Float = 1

    func pack(into bytes: inout [UInt8]) {
        level.pack(into: &bytes)
    }
}

/// What the handler saw, in order.
@MainActor
private final class Calls {
    var levels: [Float] = []
}

@MainActor
@Suite(.serialized)
struct ShaderRenderIntoTexture {

    private let words: [UInt32] = [0x0723_0203, 1, 2, 3, 4]

    private func floats(_ bytes: [UInt8]) -> [Float] {
        bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Main-queue hops and the observation's own one have run.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    /// The module, and the input as it was at the call.
    @Test
    func aRenderCarriesTheModuleAndTheInputNow() {
        let tint = Tint()
        let texture = renderTexture(size: Size(width: 4, height: 4)) { Color.clear }
        let shader = SpirvFunction(spirv: words, input: tint)
        shader.render(into: texture)
        tint.level = 5
        #expect(texture.pendingShader?.words == words)
        #expect(texture.pendingShader.map { floats($0.bytes) } == [1])
    }

    /// Whichever was asked for last: a view render after it replaces it.
    @Test
    func aViewRenderReplacesIt() {
        let texture = renderTexture(size: Size(width: 4, height: 4)) { Color.clear }
        SpirvFunction(spirv: words).render(into: texture)
        #expect(texture.pendingShader != nil)
        texture.render()
        #expect(texture.pendingShader == nil)
    }

    @Test
    func renderTextureMakesOneAndRendersIntoIt() {
        let texture = SpirvFunction(spirv: words).renderTexture(size: Size(width: 8, height: 4), scale: 2)
        #expect(texture.size == Size(width: 8, height: 4))
        #expect(texture.pixelWidth == 16 && texture.pixelHeight == 8)
        #expect(texture.pendingShader?.words == words)
    }

    /// Not for the values as they are, only for each change after.
    @Test
    func observeCallsBackOnEachChange() async {
        let tint = Tint()
        let calls = Calls()
        SpirvFunction(spirv: words, input: tint).observe { shader in
            calls.levels.append(shader.input.level)
            return true
        }
        await settle()
        #expect(calls.levels.isEmpty)
        tint.level = 2
        await settle()
        tint.level = 3
        await settle()
        #expect(calls.levels == [2, 3])
    }

    /// `false` stops it: the change it answered is the last one it sees.
    @Test
    func returningFalseStopsWatching() async {
        let tint = Tint()
        let calls = Calls()
        SpirvFunction(spirv: words, input: tint).observe { shader in
            calls.levels.append(shader.input.level)
            return calls.levels.count < 2
        }
        for level: Float in [2, 3, 4, 5] {
            tint.level = level
            await settle()
        }
        #expect(calls.levels == [2, 3])
    }
}
