//
//  SkiaCanvasViewTests.swift
//  NucleantUITests
//
//  `SkiaCanvasView`: an object drawing with the Skia API on the canvas the
//  views around it are drawn on — rendered on the GPU by `renderImage` and
//  read back pixel by pixel — and the command it puts in the list.
//

import Testing
import NucleantSkia
@testable import NucleantUI

/// Fills a rect of its canvas with one color, and logs its callbacks and
/// the sizes they were handed.
@MainActor
private final class Fill: @MainActor SkiaRenderContext {
    let color: SIMD4<Float>
    let pos: SIMD2<Float>
    /// `nil` fills the whole size it is handed.
    let size: SIMD2<Float>?
    let paint = SkPaint()
    var calls: [String] = []
    var sizes: [SIMD2<Float>] = []

    init(_ color: SIMD4<Float>, pos: SIMD2<Float> = .zero, size: SIMD2<Float>? = nil) {
        self.color = color
        self.pos = pos
        self.size = size
    }

    func onAppear(context: borrowing SkCanvas, size: SIMD2<Float>) {
        calls.append("appear")
        paint.setColor4f(color)
    }

    func update(context: borrowing SkCanvas, size: SIMD2<Float>) {
        calls.append("update")
        sizes.append(size)
        context.drawRect(pos: pos, size: self.size ?? size, paint: paint)
    }
}

/// Reads a `@State` slot while it draws.
@MainActor
private final class Reads: @MainActor SkiaRenderContext {
    let storage: StateStorage<Int>

    init(_ storage: StateStorage<Int>) {
        self.storage = storage
    }

    func onAppear(context: borrowing SkCanvas, size: SIMD2<Float>) {}

    func update(context: borrowing SkCanvas, size: SIMD2<Float>) {
        _ = storage.read()
    }
}

private let red = SIMD4<Float>(1, 0, 0, 1)

@MainActor
@Suite(.serialized)
struct SkiaCanvasViewTests {

    /// The pixel at (x, y), as (a, r, g, b).
    private func pixel(_ image: RasterImage, _ x: Int, _ y: Int) -> (a: Int, r: Int, g: Int, b: Int) {
        let word = image.pixels[y * image.width + x]
        return (
            Int((word >> 24) & 0xFF),
            Int((word >> 16) & 0xFF),
            Int((word >> 8) & 0xFF),
            Int(word & 0xFF)
        )
    }

    private func isRed(_ p: (a: Int, r: Int, g: Int, b: Int)) -> Bool {
        p.a == 255 && p.r == 255 && p.g == 0 && p.b == 0
    }

    /// The list a `SkiaCanvasView` of `context` placed at `rect` fills.
    private func placed(_ content: SkiaCanvasContent, in rect: Rect) -> DisplayList {
        var list = DisplayList()
        content.place(node: ContentNode(content: content), in: rect, proposal: ProposedSize(rect.size), context: DrawContext(), into: &list)
        return list
    }

    private func content<C: SkiaRenderContext>(
        _ context: C,
        id: Int = 0,
        reader: PositionHandle = ViewPosition(parent: nil, key: 0).handle,
        slot: RenderSlot? = nil
    ) -> SkiaCanvasContent {
        SkiaCanvasContent(
            key: RenderNodeKey(
                slot: slot ?? RenderSlot(position: reader),
                identity: ViewIdentity(type: ObjectIdentifier(Int.self), viewID: .unknown),
                id: id
            ),
            reader: reader,
            onAppear: { canvas, size in context.onAppear(context: canvas, size: size) },
            update: { canvas, size in context.update(context: canvas, size: size) }
        )
    }

    /// `list` drawn on the GPU, as the window's canvas draws it.
    private func draw(_ list: DisplayList) throws {
        _ = try #require(OffscreenGPU.shared.image(of: list, width: 10, height: 10, scale: 1))
    }

    // MARK: - Drawn on the shared canvas

    @Test func drawsAtTheFramesOriginCutToTheFrame() {
        // More than the frame: what lands outside it is cut.
        let fill = Fill(red, pos: SIMD2(-10, -10), size: SIMD2(100, 100))
        let image = renderImage(size: Size(width: 40, height: 40)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 10, height: 20)
                    SkiaCanvasView(context: fill).frame(width: 20, height: 20)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        #expect(isRed(pixel(image, 15, 5)))
        #expect(isRed(pixel(image, 29, 19)))
        #expect(pixel(image, 5, 5).a == 0)
        #expect(pixel(image, 35, 5).a == 0)
        #expect(pixel(image, 15, 25).a == 0)
        #expect(fill.sizes == [SIMD2(20, 20)])
        #expect(fill.calls == ["appear", "update"], "onAppear first, then update")
    }

    @Test func drawsInPointsAtAnyScale() {
        let fill = Fill(red, size: SIMD2(10, 10))
        let image = renderImage(size: Size(width: 20, height: 20), scale: 2) {
            SkiaCanvasView(context: fill)
        }
        #expect(image.width == 40 && image.height == 40)
        // Ten points is twenty pixels.
        #expect(isRed(pixel(image, 19, 19)))
        #expect(pixel(image, 21, 21).a == 0)
        #expect(fill.sizes == [SIMD2(20, 20)], "the size is the frame's in points, not pixels")
    }

    @Test func drawsInPaintOrderWithTheViewsAroundIt() {
        // Blue under it, red on its left half, green over its middle.
        let image = renderImage(size: Size(width: 20, height: 20)) {
            ZStack {
                Color(red: 0, green: 0, blue: 1)
                SkiaCanvasView(context: Fill(red, size: SIMD2(10, 20)))
                Color(red: 0, green: 1, blue: 0).frame(width: 4, height: 4)
            }
        }
        #expect(isRed(pixel(image, 2, 2)))
        let under = pixel(image, 17, 2)
        #expect(under.a == 255 && under.b == 255 && under.r == 0)
        let over = pixel(image, 10, 10)
        #expect(over.a == 255 && over.g == 255 && over.r == 0)
    }

    @Test func opacityFadesWhatItDraws() {
        let image = renderImage(size: Size(width: 10, height: 10)) {
            SkiaCanvasView(context: Fill(red)).opacity(0.5)
        }
        let p = pixel(image, 5, 5)
        #expect(abs(p.a - 128) <= 2)
        #expect(p.g == 0 && p.b == 0)
    }

    // MARK: - Its command

    @Test func sameObjectIsTheSameInput() {
        // One call site, as a parent's body is from one build to the next.
        func view(_ context: Fill) -> SkiaCanvasView<Fill> { SkiaCanvasView(context: context) }
        let one = Fill(red)
        let other = Fill(red)
        #expect(view(one)._isEquivalent(to: view(one)))
        #expect(!view(one)._isEquivalent(to: view(other)))
    }

    @Test func nodeIsRedrawnOnlyWhenTheViewWasRebuilt() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        let fill = Fill(red)
        let built = content(fill)
        let first = placed(built, in: rect)
        // The same content placed twice is the same command…
        #expect(first.commands == placed(built, in: rect).commands)
        // …a rebuilt view is a new one.
        #expect(first.commands != placed(content(fill), in: rect).commands)
        // Placing alone draws nothing: the renderer runs it.
        #expect(fill.calls.isEmpty)
    }

    // MARK: - onAppear

    @Test func onAppearRunsOnceUpdateEveryDraw() throws {
        let fill = Fill(red)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        let slot = RenderSlot(position: ViewPosition(parent: nil, key: 0).handle)
        try draw(placed(content(fill, slot: slot), in: rect))
        // Drawn again — the view rebuilt, or the canvas redrawn for another.
        try draw(placed(content(fill, slot: slot), in: rect))
        try draw(placed(content(fill, slot: slot), in: rect))
        #expect(fill.calls == ["appear", "update", "update", "update"])
    }

    @Test func aNewIDAppearsAgain() throws {
        let fill = Fill(red)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        let slot = RenderSlot(position: ViewPosition(parent: nil, key: 0).handle)
        try draw(placed(content(fill, id: 1, slot: slot), in: rect))
        try draw(placed(content(fill, id: 2, slot: slot), in: rect))
        try draw(placed(content(fill, id: 2, slot: slot), in: rect))
        #expect(fill.calls == ["appear", "update", "appear", "update", "update"])
    }

    @Test func anotherViewAppearsOnItsOwn() throws {
        let fill = Fill(red)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        // A view of its own, at its own slot: an appearance of its own.
        try draw(placed(content(fill, slot: RenderSlot(position: nil)), in: rect))
        try draw(placed(content(fill, slot: RenderSlot(position: nil)), in: rect))
        #expect(fill.calls == ["appear", "update", "appear", "update"])
    }

    @Test func eachTreeRenderedIsANewAppearance() {
        let fill = Fill(red)
        _ = renderImage(size: Size(width: 10, height: 10)) { SkiaCanvasView(context: fill) }
        _ = renderImage(size: Size(width: 10, height: 10)) { SkiaCanvasView(context: fill) }
        #expect(fill.calls == ["appear", "update", "appear", "update"])
    }

    @Test func neverTheSameCommandAsACanvas() {
        // Built side by side, a `Canvas` and a `SkiaCanvasView` at one frame
        // are different commands, so one swapped for the other redraws.
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        for _ in 0..<3 {
            let canvas = CanvasContent(reader: ViewPosition(parent: nil, key: 0).handle, environment: EnvironmentValues()) { _, _ in }
            var list = DisplayList()
            canvas.place(node: ContentNode(content: canvas), in: rect, proposal: ProposedSize(rect.size), context: DrawContext(), into: &list)
            #expect(list.commands != placed(content(Fill(red)), in: rect).commands)
        }
    }

    @Test func emptyFrameDrawsNothing() {
        let list = placed(content(Fill(red)), in: Rect(x: 0, y: 0, width: 0, height: 10))
        #expect(list.isEmpty)
    }

    @Test func whatUpdateReadsIsTheViews() throws {
        let position = ViewPosition(parent: nil, key: 0)
        let reader = position.handle
        let storage = StateStorage(1, owner: ViewPosition(parent: nil, key: 1).handle)
        try draw(placed(content(Reads(storage), reader: reader), in: Rect(x: 0, y: 0, width: 10, height: 10)))
        var readers: [PositionHandle] = []
        storage.readers.forEachReader(reachedBy: []) { readers.append($0) }
        #expect(readers.contains { $0 === reader })
        _ = position
    }
}
