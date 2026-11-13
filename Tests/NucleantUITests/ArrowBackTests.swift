//
//  ArrowBackTests.swift
//  NucleantUITests
//
//  `ArrowBack`, the back button's chevron as a shape: Material's
//  `arrow_back_ios_new` polygon, kept in proportion and centred in its
//  frame, and, as a screen's own back button, drawn just as the stack draws
//  its chevron, in whatever style it is filled with.
//

import Testing
@testable import NucleantUI

/// A stack with one screen pushed on its root, the pushed screen drawing
/// its own back button: `ArrowBack` filled with `style`, where the stack
/// would have drawn its chevron.
@View
struct ArrowBackStack {
    let style: ShapeStyle
    @State private var path = NavigationPath([1])

    var body: some View {
        NavigationStack(path: $path) {
            BarTestStrip(log: Log(), name: "root")
                .navigationTitle("Root")
                .navigationDestination(for: Int.self) { _ in
                    ArrowBackScreen(style: style)
                }
        }
    }
}

@View
struct ArrowBackScreen {
    let style: ShapeStyle
    @Environment(\.navigationRouter) private var router

    var body: some View {
        BarTestStrip(log: Log(), name: "page")
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ArrowBack()
                        .fill(style)
                        .frame(width: 20, height: 20)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .onTapGesture { router?.pop() }
                }
            }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ArrowBackTests {

        static let size = Size(width: 200, height: 200)

        /// The square the back button takes in a bar: 12 points in, 36
        /// points across, in the 44-point bar.
        static let square = (x: 12..<48, y: 4..<40)

        private func near(_ a: Rect, _ b: Rect) -> Bool {
            abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9
                && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
        }

        @Test func itIsTheIconsPolygon() {
            var icon = Path()
            icon.addLines([
                Point(x: 17.77, y: 3.77),
                Point(x: 16, y: 2),
                Point(x: 6, y: 12),
                Point(x: 16, y: 22),
                Point(x: 17.77, y: 20.23),
                Point(x: 9.54, y: 12),
            ])
            icon.closeSubpath()
            #expect(ArrowBack().path(in: Rect(x: 0, y: 0, width: 24, height: 24)) == icon)
        }

        @Test func itKeepsItsProportionsCentredInItsFrame() {
            // 40 × 20: the 24-point box scaled to 20 and centred across, at
            // 20…40, so the chevron's 6…17.77 × 2…22 lands at 25…34.81 ×
            // 1.67…18.33.
            let drawn = ArrowBack().path(in: Rect(x: 10, y: 0, width: 40, height: 20)).boundingRect
            let scale = 20.0 / 24
            #expect(near(drawn, Rect(x: 20 + 6 * scale, y: 2 * scale, width: 11.77 * scale, height: 20 * scale)))
            // 20 × 40: centred down instead.
            let tall = ArrowBack().path(in: Rect(x: 0, y: 0, width: 20, height: 40)).boundingRect
            #expect(near(tall, Rect(x: 6 * scale, y: 10 + 2 * scale, width: 11.77 * scale, height: 20 * scale)))
        }

        @Test func usedBareItFillsWithTheForegroundStyle() {
            let list = OffscreenRender(environment: EnvironmentValues()).list(
                of: ArrowBack().foregroundStyle(Color.orange),
                size: Size(width: 24, height: 24)
            )
            let fills = list.commands.compactMap {
                if case .shape(let draw) = $0 { return draw.fill }
                return nil
            }
            #expect(fills == [.color(.orange)])
        }

        /// (a, r, g, b) of each premultiplied ARGB pixel in the back
        /// button's square.
        private func square(of image: RasterImage) -> [SIMD4<Int>] {
            Self.square.y.flatMap { y in
                Self.square.x.map { x in
                    let word = image.pixels[y * image.width + x]
                    return SIMD4(Int(word >> 24), Int((word >> 16) & 0xFF), Int((word >> 8) & 0xFF), Int(word & 0xFF))
                }
            }
        }

        @Test func filledPrimaryInA20PointFrameItIsTheStacksChevron() {
            let stacks = square(of: renderImage(size: Self.size, content: BackButtonStack(log: Log())))
            let own = square(of: renderImage(size: Self.size, content: ArrowBackStack(style: .primary)))
            // The two are drawn apart, the icon from its document and the
            // shape from its path, so an edge pixel may round differently.
            let apart = zip(stacks, own).map { a, b in (0..<4).map { abs(a[$0] - b[$0]) }.max()! }
            #expect(apart.max()! <= 8)
            // And it is the chevron, not two empty squares alike.
            #expect(stacks.contains { $0.y < 60 && $0.z < 60 && $0.w < 60 })
        }

        @Test func itTakesAnyColor() {
            let image = renderImage(size: Self.size, content: ArrowBackStack(style: .color(Color(hex: 0xE0457B))))
            // The chevron's point, where the stack's chevron is dark.
            let word = image.pixels[22 * image.width + 26]
            let (r, g, b) = (Int((word >> 16) & 0xFF), Int((word >> 8) & 0xFF), Int(word & 0xFF))
            #expect(abs(r - 0xE0) <= 4 && abs(g - 0x45) <= 4 && abs(b - 0x7B) <= 4)
        }
    }
}
