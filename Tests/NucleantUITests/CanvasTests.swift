//
//  CanvasTests.swift
//  NucleantUITests
//
//  `Canvas`: its renderer drawing on the node's Skia canvas, read back from a
//  CPU surface pixel by pixel.
//

#if SKIA_MODE

import Testing
import NucleantSkia
@testable import NucleantUI

@MainActor
@Suite struct CanvasTests {
    let surface = SkSurfaces.raster(width: 100, height: 100)!

    private func pixel(_ x: Int, _ y: Int) -> SIMD4<UInt8> {
        surface.readPixel(x: x, y: y) ?? SIMD4(0, 0, 0, 0)
    }

    private func command(
        in rect: Rect,
        context: DrawContext = DrawContext(),
        _ renderer: @escaping (inout GraphicsContext, Size) -> Void
    ) -> (DrawCommand, CanvasContent) {
        let content = CanvasContent(path: [0], renderer: renderer)
        var list = DisplayList()
        content.place(node: ViewNode(content: content), in: rect, proposal: ProposedSize(rect.size), context: context, into: &list)
        return (list.commands[0], content)
    }

    /// Draw a canvas placed at `rect` onto the surface.
    private func render(
        in rect: Rect,
        context: DrawContext = DrawContext(),
        _ renderer: @escaping (inout GraphicsContext, Size) -> Void
    ) {
        var list = DisplayList()
        list.append(command(in: rect, context: context, renderer).0)
        SkiaDisplayRenderer(surface: surface).render(list)
    }

    private let red = SIMD4<UInt8>(255, 0, 0, 255)

    @Test func canvasIsAtTheFramesOrigin() {
        render(in: Rect(x: 30, y: 40, width: 50, height: 50)) { context, _ in
            context.fill(Path(Rect(x: 0, y: 0, width: 10, height: 10)), with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        #expect(pixel(35, 45) == red)
        #expect(pixel(5, 5).w == 0)
        #expect(pixel(45, 55).w == 0)
    }

    @Test func rendererReceivesTheSize() {
        var seen: Size?
        render(in: Rect(x: 5, y: 7, width: 60, height: 40)) { context, size in
            seen = size
            #expect(context.size == size)
        }
        #expect(seen == Size(width: 60, height: 40))
    }

    @Test func drawingIsCutToTheFrame() {
        render(in: Rect(x: 20, y: 20, width: 20, height: 20)) { context, _ in
            context.fill(Path(Rect(x: -10, y: -10, width: 100, height: 100)), with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        #expect(pixel(25, 25) == red)
        #expect(pixel(10, 10).w == 0)
        #expect(pixel(50, 50).w == 0)
    }

    @Test func strokeDrawsTheOutlineOnly() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            context.stroke(Path(Rect(x: 20, y: 20, width: 40, height: 40)), with: .color(.init(red: 1, green: 0, blue: 0)), lineWidth: 4)
        }
        #expect(pixel(40, 20).w > 0)
        #expect(pixel(40, 40).w == 0)
    }

    @Test func translateMovesLaterDrawing() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            context.translateBy(x: 50, y: 50)
            context.fill(Path(Rect(x: 0, y: 0, width: 10, height: 10)), with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        #expect(pixel(55, 55) == red)
        #expect(pixel(5, 5).w == 0)
    }

    @Test func layerChangesEndWithTheLayer() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            let square = Path(Rect(x: 0, y: 0, width: 10, height: 10))
            context.drawLayer { layer in
                layer.translateBy(x: 50, y: 50)
                layer.fill(square, with: .color(.init(red: 1, green: 0, blue: 0)))
            }
            context.fill(square, with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        #expect(pixel(55, 55) == red)
        #expect(pixel(5, 5) == red)
    }

    @Test func clipNarrowsLaterDrawing() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            context.clip(to: Rect(x: 0, y: 0, width: 20, height: 20))
            context.fill(Path(Rect(x: 0, y: 0, width: 50, height: 50)), with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        #expect(pixel(10, 10) == red)
        #expect(pixel(30, 30).w == 0)
    }

    @Test func opacityFadesTheFill() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            context.opacity = 0.5
            context.fill(Path(Rect(x: 0, y: 0, width: 50, height: 50)), with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        let ink = pixel(10, 10)
        #expect(ink.w > 100 && ink.w < 160)
    }

    @Test func rawCanvasIsTheNodes() {
        render(in: Rect(x: 30, y: 30, width: 50, height: 50)) { context, _ in
            let paint = SkPaint(color: SIMD4(1, 0, 0, 1))
            context.canvas.drawRect(pos: SIMD2<Float>(0, 0), size: SIMD2<Float>(10, 10), paint: paint)
        }
        #expect(pixel(35, 35) == red)
        #expect(pixel(5, 5).w == 0)
    }

    @Test func withCanvasAppliesTheContextState() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            context.translateBy(x: 50, y: 50)
            context.withCanvas { canvas in
                canvas.drawRect(pos: SIMD2<Float>(0, 0), size: SIMD2<Float>(10, 10), paint: SkPaint(color: SIMD4(1, 0, 0, 1)))
            }
        }
        #expect(pixel(55, 55) == red)
        #expect(pixel(5, 5).w == 0)
    }

    @Test func imageInAPathIsDrawnIntoItsRect() {
        // 2×2 opaque red, as premultiplied ARGB words.
        let image = RasterImage(width: 2, height: 2, pixels: [UInt32](repeating: 0xFFFF0000, count: 4))
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            var path = Path()
            path.addImage(image, in: Rect(x: 20, y: 20, width: 30, height: 30))
            context.fill(path, with: .color(.init(red: 1, green: 1, blue: 1)))
        }
        #expect(pixel(30, 30) == red)
        #expect(pixel(10, 10).w == 0)
        #expect(pixel(60, 60).w == 0)
    }

    @Test func imageInADisplayListPathIsDrawnToo() {
        let image = RasterImage(width: 2, height: 2, pixels: [UInt32](repeating: 0xFFFF0000, count: 4))
        var path = Path()
        path.addImage(image, in: Rect(x: 20, y: 20, width: 30, height: 30))
        var list = DisplayList()
        list.append(.shape(ShapeDraw(path: path, bounds: Rect(x: 0, y: 0, width: 100, height: 100), fill: .color(.init(red: 1, green: 1, blue: 1)))))
        SkiaDisplayRenderer(surface: surface).render(list)
        #expect(pixel(30, 30) == red)
        #expect(pixel(10, 10).w == 0)
    }

    @Test func textInAPathLeavesInk() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            var path = Path()
            path.addText("MMMM", at: Point(x: 5, y: 5), font: .system(size: 30))
            context.fill(path, with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        let ink = (0..<100).contains { x in (0..<60).contains { pixel(x, $0).w > 0 } }
        #expect(ink)
    }

    @Test func quadraticCurveFills() {
        render(in: Rect(x: 0, y: 0, width: 100, height: 100)) { context, _ in
            var path = Path()
            path.move(to: Point(x: 10, y: 90))
            path.addQuadCurve(to: Point(x: 90, y: 90), control: Point(x: 50, y: 10))
            path.closeSubpath()
            context.fill(path, with: .color(.init(red: 1, green: 0, blue: 0)))
        }
        #expect(pixel(50, 80) == red)
        #expect(pixel(50, 20).w == 0)
    }

    @Test func nodeIsRedrawnOnlyWhenTheViewWasRebuilt() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        let (first, content) = command(in: rect) { _, _ in }
        var again = DisplayList()
        content.place(node: ViewNode(content: content), in: rect, proposal: ProposedSize(rect.size), context: DrawContext(), into: &again)
        // The same content placed twice is the same command…
        #expect(first == again.commands[0])
        // …a rebuilt view is a new one.
        #expect(first != command(in: rect) { _, _ in }.0)
    }

    @Test func emptyFrameDrawsNothing() {
        var ran = false
        var list = DisplayList()
        let content = CanvasContent(path: [0]) { _, _ in ran = true }
        content.place(node: ViewNode(content: content), in: Rect(x: 0, y: 0, width: 0, height: 10), proposal: ProposedSize(Size(width: 0, height: 10)), context: DrawContext(), into: &list)
        #expect(list.isEmpty)
        #expect(!ran)
    }
}

#endif
