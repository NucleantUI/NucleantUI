//
//  SvgViewTests.swift
//  NucleantUITests
//
//  `SvgImage` and `SvgView`: the size a document says it is, how the view
//  lays out around it, and the drawing — through Skia into a CPU surface,
//  and through ThorVG as `renderImage` rasterizes it.
//

import Foundation
import Testing
import NucleantSkia
@testable import NucleantUI

@MainActor
@Suite
struct SvgViewTests {

    /// A red square over its whole 24 × 24 box.
    static let square = SvgImage(markup: """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\
        <rect width="24" height="24" fill="#ff0000"/></svg>
        """)!

    /// A blue band twice as wide as it is tall, sized by its viewBox alone.
    static let wide = SvgImage(markup: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20">\
        <rect width="40" height="20" fill="#0000ff"/></svg>
        """)!

    /// A two-tone icon: the left half at 30 % opacity, the right half solid.
    static let twoTone = SvgImage(markup: """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\
        <rect width="12" height="24" opacity=".3"/><rect x="12" width="12" height="24"/></svg>
        """)!

    private static let green = Color(red: 0, green: 1, blue: 0)

    // MARK: - The document's size

    @Test func sizeIsTheWidthAndHeight() {
        let image = SvgImage(markup: #"<svg xmlns="http://www.w3.org/2000/svg" width="48" height="32" viewBox="0 0 12 12"/>"#)
        #expect(image?.size == Size(width: 48, height: 32))
    }

    @Test func sizeWithoutWidthAndHeightIsTheViewBox() {
        #expect(Self.wide.size == Size(width: 40, height: 20))
    }

    @Test func sizeInPercentIsTheViewBox() {
        let image = SvgImage(markup: #"<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 40 20"/>"#)
        #expect(image?.size == Size(width: 40, height: 20))
    }

    @Test func noSizeAndNoViewBoxIsTheBrowsersDefault() {
        let image = SvgImage(markup: #"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
        #expect(image?.size == Size(width: 300, height: 150))
    }

    @Test func somethingElseIsNoDocument() {
        #expect(SvgImage(markup: "not an svg") == nil)
        #expect(SvgImage(data: Data()) == nil)
        #expect(SvgImage(contentsOf: URL(fileURLWithPath: "/nonexistent/icon.svg")) == nil)
    }

    @Test func loadsFromAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SvgViewTests-\(UUID().uuidString).svg")
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"/>"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SvgImage(contentsOf: url)?.size == Size(width: 16, height: 16))
    }

    // MARK: - Layout

    /// The SVG draws `view` makes when laid out at `size`.
    private func draws<V: View>(_ view: V, size: Size = Size(width: 100, height: 100)) -> [SvgDraw] {
        OffscreenRender(environment: EnvironmentValues()).list(of: view, size: size).commands.compactMap {
            if case .svg(let draw) = $0 { return draw }
            return nil
        }
    }

    @Test func drawnAtItsOwnSize() {
        let frames = draws(ZStack { SvgView(Self.square) }).map(\.frame)
        #expect(frames == [Rect(x: 38, y: 38, width: 24, height: 24)])
    }

    @Test func resizableTakesWhatItIsOffered() {
        let frames = draws(SvgView(Self.square).resizable()).map(\.frame)
        #expect(frames == [Rect(x: 0, y: 0, width: 100, height: 100)])
    }

    @Test func scaledToFitTakesTheDocumentsProportions() {
        let frames = draws(SvgView(Self.wide).resizable().scaledToFit()).map(\.frame)
        #expect(frames == [Rect(x: 0, y: 25, width: 100, height: 50)])
    }

    @Test func theDocumentFitsItsFrameInProportion() {
        let box = Self.wide.fittedRect(in: Rect(x: 0, y: 0, width: 100, height: 100))
        #expect(box == Rect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func originalKeepsItsOwnColors() {
        let tints = draws(SvgView(Self.square).foregroundStyle(Self.green)).map(\.tint)
        #expect(tints == [nil])
    }

    @Test func templateTakesTheForegroundStyle() {
        let tints = draws(SvgView(Self.square).renderingMode(.template).foregroundStyle(Self.green)).map(\.tint)
        #expect(tints == [.color(Self.green)])
    }

    @Test func templateIsResolvedForTheColorScheme() {
        let view = SvgView(Self.square).renderingMode(.template)
            .foregroundStyle(.primary)
            .colorScheme(.dark)
        let dark = HierarchicalShapeStyle.primary.colors.dark
        #expect(draws(view).map(\.tint) == [.color(dark)])
    }

    @Test func opacityTravelsWithTheDraw() {
        let opacities = draws(SvgView(Self.square).opacity(0.5)).map(\.opacity)
        #expect(opacities == [0.5])
    }

    // MARK: - Drawing with Skia

    let surface = SkSurfaces.raster(width: 100, height: 100)!

    private func skia(_ draw: SvgDraw) {
        var list = DisplayList()
        list.append(.svg(draw))
        SkiaDisplayRenderer(surface: surface).render(list)
    }

    private func pixel(_ x: Int, _ y: Int) -> SIMD4<UInt8> {
        surface.readPixel(x: x, y: y) ?? SIMD4(0, 0, 0, 0)
    }

    @Test func skiaDrawsTheDocumentInItsFrame() {
        skia(SvgDraw(image: Self.square, frame: Rect(x: 10, y: 10, width: 24, height: 24)))
        #expect(pixel(20, 20) == SIMD4(255, 0, 0, 255))
        #expect(pixel(5, 5).w == 0)
        #expect(pixel(40, 40).w == 0)
    }

    @Test func skiaScalesTheDocumentToFitInProportion() {
        skia(SvgDraw(image: Self.wide, frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        #expect(pixel(50, 30) == SIMD4(0, 0, 255, 255))
        #expect(pixel(50, 70) == SIMD4(0, 0, 255, 255))
        #expect(pixel(50, 20).w == 0)
        #expect(pixel(50, 80).w == 0)
    }

    @Test func skiaPaintsATemplateInItsTint() {
        skia(SvgDraw(image: Self.square, frame: Rect(x: 0, y: 0, width: 50, height: 50), tint: .color(Self.green)))
        #expect(pixel(25, 25) == SIMD4(0, 255, 0, 255))
        #expect(pixel(75, 75).w == 0)
    }

    @Test func skiaTintKeepsTheDocumentsOwnOpacity() {
        skia(SvgDraw(image: Self.twoTone, frame: Rect(x: 0, y: 0, width: 48, height: 48), tint: .color(Self.green)))
        #expect(abs(Int(pixel(12, 24).w) - 77) <= 2)
        #expect(pixel(36, 24) == SIMD4(0, 255, 0, 255))
    }

    @Test func skiaFadesByTheOpacity() {
        skia(SvgDraw(image: Self.square, frame: Rect(x: 0, y: 0, width: 50, height: 50), opacity: 0.5))
        #expect(abs(Int(pixel(25, 25).w) - 128) <= 2)
    }

    // MARK: - Drawing with ThorVG (`renderImage`)

    /// The pixel at (x, y) of a premultiplied ARGB image, as (a, r, g, b).
    private func argb(_ image: RasterImage, _ x: Int, _ y: Int) -> SIMD4<Int> {
        let word = image.pixels[y * image.width + x]
        return SIMD4(Int(word >> 24), Int((word >> 16) & 0xFF), Int((word >> 8) & 0xFF), Int(word & 0xFF))
    }

    @Test func renderImageDrawsTheDocument() {
        let image = renderImage(size: Size(width: 48, height: 48)) {
            SvgView(Self.square).resizable()
        }
        #expect(argb(image, 24, 24) == SIMD4(255, 255, 0, 0))
    }

    @Test func renderImageFitsTheDocumentInProportion() {
        let image = renderImage(size: Size(width: 100, height: 100)) {
            SvgView(Self.wide).resizable()
        }
        #expect(argb(image, 50, 30) == SIMD4(255, 0, 0, 255))
        #expect(argb(image, 50, 70) == SIMD4(255, 0, 0, 255))
        #expect(argb(image, 50, 20).x == 0)
        #expect(argb(image, 50, 80).x == 0)
    }

    @Test func renderImagePaintsATemplateInItsTint() {
        let image = renderImage(size: Size(width: 48, height: 48)) {
            SvgView(Self.twoTone).resizable()
                .renderingMode(.template)
                .foregroundStyle(Self.green)
        }
        #expect(abs(argb(image, 12, 24).x - 77) <= 2)
        #expect(argb(image, 36, 24) == SIMD4(255, 0, 255, 0))
    }

    @Test func renderImageFadesByTheOpacity() {
        let image = renderImage(size: Size(width: 48, height: 48)) {
            SvgView(Self.square).resizable().opacity(0.5)
        }
        #expect(abs(argb(image, 24, 24).x - 128) <= 2)
    }

    // MARK: - Both renderers

    /// Material's "contacts" icon: an invisible full-box path, then the
    /// glyph, which stops short of the box on the left and right.
    static let contacts = SvgImage(markup: """
        <svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 0 24 24" width="24">\
        <path d="M0 0h24v24H0zm0 0h24v24H0zm0 0h24v24H0z" fill="none"/>\
        <path d="M20 0H4v2h16V0zM4 24h16v-2H4v2zM20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm-8 \
        2.75c1.24 0 2.25 1.01 2.25 2.25s-1.01 2.25-2.25 2.25S9.75 10.24 9.75 9 10.76 6.75 12 6.75zM17 17H7v-1.5c0-1.67 3.33-2.5 \
        5-2.5s5 .83 5 2.5V17z"/></svg>
        """)!

    /// The box holding every pixel with alpha over 40: (minX, minY, maxX, maxY).
    private func ink(width: Int, height: Int, alpha: (Int, Int) -> Int) -> SIMD4<Int>? {
        var box: SIMD4<Int>?
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) > 40 {
                box = box.map { SIMD4(min($0.x, x), min($0.y, y), max($0.z, x), max($0.w, y)) } ?? SIMD4(x, y, x, y)
            }
        }
        return box
    }

    @Test func bothRenderersPutTheDocumentInTheSamePlace() {
        let frame = Rect(x: 13, y: 7, width: 60, height: 80)
        let view = ZStack(alignment: .topLeading) {
            SvgView(Self.contacts).resizable()
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        let thorImage = renderImage(size: Size(width: 100, height: 100), content: view)
        let thor = ink(width: 100, height: 100) { x, y in argb(thorImage, x, y).x }
        skia(SvgDraw(image: Self.contacts, frame: frame))
        let skia = ink(width: 100, height: 100) { x, y in Int(pixel(x, y).w) }
        #expect(thor != nil)
        #expect(thor == skia)
        // 60 wide, so the 24-point icon is drawn 60 tall, centered in the 80:
        // its glyph runs x 2…22 and y 0…24 of the 24, at 2.5×.
        if let skia {
            #expect(abs(skia.x - 18) <= 1 && abs(skia.z - 67) <= 1)
            #expect(abs(skia.y - 17) <= 1 && abs(skia.w - 76) <= 1)
        }
    }
}
