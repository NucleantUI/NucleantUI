//
//  RenderImageTests.swift
//  NucleantUITests
//
//  `renderImage` — a view tree rasterized with no window and no GPU. The one
//  offscreen path a test can cover end to end: the GPU sibling
//  (`RenderTexture`) needs an engine, which this target has none of.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
@Suite(.serialized)
struct OffscreenImages {

    /// The pixel at (x, y), as (a, r, g, b).
    func pixel(_ image: RasterImage, _ x: Int, _ y: Int) -> (a: Int, r: Int, g: Int, b: Int) {
        let word = image.pixels[y * image.width + x]
        return (
            Int((word >> 24) & 0xFF),
            Int((word >> 16) & 0xFF),
            Int((word >> 8) & 0xFF),
            Int(word & 0xFF)
        )
    }

    @Test
    func aColorFillsTheImage() {
        let image = renderImage(size: Size(width: 8, height: 4)) {
            Color(red: 1, green: 0, blue: 0)
        }
        #expect(image.width == 8)
        #expect(image.height == 4)
        for y in 0..<4 {
            for x in 0..<8 {
                let p = pixel(image, x, y)
                #expect(p.a == 255)
                #expect(p.r == 255)
                #expect(p.g == 0)
                #expect(p.b == 0)
            }
        }
    }

    @Test
    func scaleMultipliesThePixelsNotTheLayout() {
        let content = Color(red: 0, green: 0, blue: 1)
        let single = renderImage(size: Size(width: 10, height: 6), scale: 1, content: content)
        let double = renderImage(size: Size(width: 10, height: 6), scale: 2, content: content)
        #expect(single.width == 10 && single.height == 6)
        #expect(double.width == 20 && double.height == 12)
        // The same colour either way — the layout was the same size.
        #expect(pixel(double, 19, 11) == pixel(single, 9, 5))
    }

    @Test
    func anEmptyTreeIsTransparent() {
        let image = renderImage(size: Size(width: 4, height: 4)) { EmptyView() }
        #expect(image.width == 4 && image.height == 4)
        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test
    func aZeroSizeIsAnEmptyImage() {
        let image = renderImage(size: .zero) { Color(red: 1, green: 1, blue: 1) }
        #expect(image.width == 0)
        #expect(image.height == 0)
        #expect(image.pixels.isEmpty)
    }

    @Test
    func aHalfWidthChildFillsHalfTheImage() {
        // Laid out at 20×10, so the frame takes the left half and the rest of
        // the image stays transparent: the tree really was laid out against
        // the size it was given, not against a window.
        let image = renderImage(size: Size(width: 20, height: 10)) {
            HStack(spacing: 0) {
                Color(red: 0, green: 1, blue: 0).frame(width: 10)
                Spacer()
            }
        }
        #expect(pixel(image, 2, 5).g == 255)
        #expect(pixel(image, 2, 5).a == 255)
        #expect(image.pixels[5 * 20 + 17] == 0)
    }

    @Test
    func aTrailingFormIsTheSameAsTheFunction() {
        let size = Size(width: 6, height: 6)
        let direct = renderImage(size: size) { Color(red: 0.2, green: 0.4, blue: 0.6) }
        let trailing = Color(red: 0.2, green: 0.4, blue: 0.6).image(size: size)
        #expect(direct.pixels == trailing.pixels)
    }

    /// The point of rooting an offscreen tree at `OffscreenRender.rootIndex`:
    /// a render leaves the window's frame alone.
    @Test
    func anOffscreenRenderDirtiesNothing() {
        _ = Invalidator.shared.consume()
        _ = renderImage(size: Size(width: 8, height: 8)) {
            Color(red: 1, green: 1, blue: 0)
        }
        let work = Invalidator.shared.consume()
        #expect(work.paths.isEmpty)
        #expect(work.full == false)
    }

    /// And the other half of being a snapshot: no pass ran, so the window's
    /// current host is untouched.
    @Test
    func anOffscreenRenderRunsNoPass() {
        #expect(ShaderHost.current == nil)
        _ = renderImage(size: Size(width: 8, height: 8)) { Color(red: 0, green: 0, blue: 0) }
        #expect(ShaderHost.current == nil)
        #expect(AnimationStore.current == nil)
    }
}
