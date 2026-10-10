//
//  RenderTextureTests.swift
//  NucleantUITests
//
//  `RenderTexture` without a GPU: its layout, its content, its snapshot
//  semantics and the fit rule of `tex.view()`.
//
//  There is no `NucleantRenderEngine` in this target, so what is covered here
//  is everything *above* the image: the tree is driven, the display list is
//  the same one the CPU path draws, no window pass is disturbed, and a
//  texture with no engine behind it degrades rather than crashing. The image
//  itself is verified in the demo, where `tex.image()` is asserted against
//  `renderImage` of the same tree.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
@Observable
final class Level {
    var value: Int
    init(value: Int) { self.value = value }
}

@View
private struct Swatch {
    let level: Int

    var body: some View {
        Color(red: Double(level) / 10, green: 0, blue: 0)
    }
}

/// A view with state of its own, to show what survives a re-render and what
/// does not drive one.
@View
private struct Counting {
    let log: Log
    @State private var runs = 0

    var body: some View {
        log("body \(runs)")
        return Color(red: 0, green: 1, blue: 0)
    }
}

@MainActor
@Suite(.serialized)
struct RenderTextures {

    @Test
    func aTextureIsTheSizeItWasMadeAt() {
        let tex = renderTexture(size: Size(width: 64, height: 32), scale: 2) {
            Swatch(level: 5)
        }
        #expect(tex.size == Size(width: 64, height: 32))
        #expect(tex.scale == 2)
        #expect(tex.pixelWidth == 128)
        #expect(tex.pixelHeight == 64)
    }

    /// No engine in this target, so there is no image — and nothing crashes
    /// for the want of one. A texture made before a window exists keeps its
    /// content and takes a canvas when one appears.
    @Test
    func withNoEngineThereIsNoImageAndNoCrash() {
        let tex = renderTexture(size: Size(width: 16, height: 16)) { Swatch(level: 9) }
        #expect(tex.hasContent == false)
        #expect(tex.image() == nil)
        #expect(tex.gpuImage == nil)
        #expect(tex.content.commands.isEmpty == false)
    }

    /// The texture draws exactly what `renderImage` draws: same tree, same
    /// size, same list. This is the parity the GPU path then has to match.
    @Test
    func theTextureDrawsWhatRenderImageDraws() {
        let size = Size(width: 24, height: 12)
        let tex = renderTexture(size: size, scale: 2) { Swatch(level: 7) }
        let fromTexture = OffscreenRaster.image(of: tex.content, size: size, scale: 2)
        let fromImage = renderImage(size: size, scale: 2) { Swatch(level: 7) }
        #expect(fromTexture.width == fromImage.width)
        #expect(fromTexture.height == fromImage.height)
        #expect(fromTexture.pixels == fromImage.pixels)
    }

    /// `update { }` is how new content gets in; the texture keeps its size
    /// and scale through it.
    @Test
    func updateReplacesTheContent() {
        let size = Size(width: 10, height: 10)
        let tex = renderTexture(size: size) { Swatch(level: 2) }
        let before = OffscreenRaster.image(of: tex.content, size: size, scale: 1)
        tex.update { Swatch(level: 9) }
        let after = OffscreenRaster.image(of: tex.content, size: size, scale: 1)
        #expect(before.pixels != after.pixels)
        #expect(after.pixels == renderImage(size: size) { Swatch(level: 9) }.pixels)
        #expect(tex.size == size)
    }

    /// A render re-evaluates the view, so a model it reads shows its current
    /// value — and only then, which is what "snapshot" means.
    @Test
    func renderPicksUpTheModelAndNothingElseDoes() {
        let level = Level(value: 1)
        let size = Size(width: 8, height: 8)
        let tex = renderTexture(size: size) { Swatch(level: level.value) }
        let first = OffscreenRaster.image(of: tex.content, size: size, scale: 1)

        level.value = 9
        // No render: the texture still holds what it drew.
        let unchanged = OffscreenRaster.image(of: tex.content, size: size, scale: 1)
        #expect(unchanged.pixels == first.pixels)

        tex.render()
        let refreshed = OffscreenRaster.image(of: tex.content, size: size, scale: 1)
        #expect(refreshed.pixels != first.pixels)
        #expect(refreshed.pixels == renderImage(size: size) { Swatch(level: 9) }.pixels)
    }

    /// A model an offscreen tree read must not dirty the window's frame: the
    /// tree is rooted at a slot no window tree can produce, and `Invalidator`
    /// drops paths from it. Without that, every write to a model a texture
    /// read would send the window into a full rebuild for a tree it cannot
    /// see.
    @Test
    func anOffscreenReadNeverDirtiesTheWindow() {
        let level = Level(value: 1)
        _ = renderTexture(size: Size(width: 8, height: 8)) { Swatch(level: level.value) }
        _ = Invalidator.shared.consume()
        level.value = 2
        let work = Invalidator.shared.consume()
        #expect(work.paths.isEmpty)
        #expect(work.full == false)
    }

    /// The tree is kept across renders, so a view that is still equivalent is
    /// reused and its `@State` keeps its value rather than starting over.
    @Test
    func stateInsideSurvivesARender() {
        let log = Log()
        let tex = renderTexture(size: Size(width: 8, height: 8)) { Counting(log: log) }
        #expect(log.take() == ["body 0"])
        tex.render()
        // Same view, same inputs, nothing dirty: the standing node is reused
        // and the body does not run again.
        #expect(log.take() == [])
    }

    /// `tex.view()` follows `Image`'s rule: its own size, unless resizable.
    @Test
    func theViewIsDrawnAtTheTexturesSize() {
        let tex = renderTexture(size: Size(width: 40, height: 20)) { Swatch(level: 3) }
        let key = RenderNodeKey(
            path: [0],
            identity: ViewIdentity(type: ObjectIdentifier(RenderTextureView.self), viewID: .unknown)
        )
        let fixed = RenderTextureContent(key: key, texture: tex, isResizable: false)
        let node = ViewNode(content: fixed)
        let offered = ProposedSize(Size(width: 500, height: 500))
        #expect(fixed.sizeThatFits(offered, node: node) == Size(width: 40, height: 20))
        #expect(fixed.flexibility(along: .horizontal, node: node) == .fixed)

        let resizable = RenderTextureContent(key: key, texture: tex, isResizable: true)
        let resizableNode = ViewNode(content: resizable)
        #expect(resizable.sizeThatFits(offered, node: resizableNode) == Size(width: 500, height: 500))
        #expect(resizable.flexibility(along: .horizontal, node: resizableNode) == .flexible)
        // Unconstrained on an axis, it falls back to the texture's own size.
        #expect(
            resizable.sizeThatFits(ProposedSize(width: nil, height: nil), node: resizableNode)
                == Size(width: 40, height: 20)
        )
    }

    /// Hosting one with no engine lays out and draws nothing, rather than
    /// reaching for a registry that is not there.
    @Test
    func hostingOneWithNoEngineIsHarmless() async {
        let tex = renderTexture(size: Size(width: 20, height: 20)) { Swatch(level: 4) }
        let harness = Harness(tex.view())
        await harness.settle()
        #expect(harness.host.size == Size(width: 200, height: 200))
    }

    @Test
    func aZeroSizedTextureRendersNothing() {
        let tex = renderTexture(size: .zero) { Swatch(level: 1) }
        #expect(tex.pixelWidth == 0)
        #expect(tex.hasContent == false)
        #expect(tex.content.commands.isEmpty)
    }
}
