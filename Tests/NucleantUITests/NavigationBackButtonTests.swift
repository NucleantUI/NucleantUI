//
//  NavigationBackButtonTests.swift
//  NucleantUITests
//
//  A pushed screen's bar draws Material's `arrow_back_ios_new` chevron as
//  its back button, alone and in the primary label color, as iOS 26 draws
//  it, where it used to draw a blue "‹ Back". A tap anywhere in its
//  36-point square pops.
//
//  The bar is 44 tall with 12 points of padding, so the square sits at
//  12…48 × 4…40 and the 20-point chevron at 20…40 × 12…32.
//

import Testing
@testable import NucleantUI

/// A stack with one screen pushed on its root, both a `BarTestStrip`.
@View
struct BackButtonStack {
    let log: Log
    @State private var path = NavigationPath([1])

    var body: some View {
        NavigationStack(path: $path) {
            BarTestStrip(log: log, name: "root")
                // Titled, so the root keeps its bar after the pop.
                .navigationTitle("Root")
                .navigationDestination(for: Int.self) { page in
                    BarTestStrip(log: log, name: "page \(page)")
                }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct NavigationBackButtonTests {

        static let size = Size(width: 200, height: 200)
        static let chevron = Rect(x: 20, y: 12, width: 20, height: 20)
        /// The strip at the top of whichever screen is showing.
        static let underBar = Point(x: 100, y: 54)

        /// What a stack draws with `pushed` screens on its root.
        private func list(pushed: [Int], dark: Bool = false) -> DisplayList {
            var environment = EnvironmentValues()
            environment.colorScheme = dark ? .dark : .light
            let stack = NavigationStack(path: .constant(NavigationPath(pushed))) {
                Color.red
                    .navigationDestination(for: Int.self) { _ in Color.green }
            }
            return OffscreenRender(environment: environment).list(of: stack, size: Self.size)
        }

        private func chevrons(_ list: DisplayList) -> [SvgDraw] {
            list.commands.compactMap {
                if case .svg(let draw) = $0, draw.image === Icons.shared.back { return draw }
                return nil
            }
        }

        private func texts(_ list: DisplayList) -> [String] {
            list.commands.compactMap {
                if case .text(let draw) = $0 { return draw.string }
                return nil
            }
        }

        @Test func theIconIsMaterialsChevronInItsBox() {
            #expect(Icons.shared.back.size == Size(width: 24, height: 24))
        }

        @Test func aPushedScreensBarDrawsTheChevronAlone() {
            let list = list(pushed: [1])
            #expect(chevrons(list).map(\.frame) == [Self.chevron])
            // No "‹ Back", nor a title beside it.
            #expect(!texts(list).contains { $0.contains("Back") || $0.contains("‹") })
        }

        @Test func theRootHasNoBackButton() {
            #expect(chevrons(list(pushed: [])).isEmpty)
        }

        @Test func itIsThePrimaryLabelColorNotTheAccent() {
            let (light, dark) = (HierarchicalShapeStyle.primary.colors.light, HierarchicalShapeStyle.primary.colors.dark)
            #expect(chevrons(list(pushed: [1])).map(\.tint) == [.color(light)])
            #expect(chevrons(list(pushed: [1], dark: true)).map(\.tint) == [.color(dark)])
        }

        @Test func itIsDrawnOnTheGPU() {
            let image = renderImage(size: Self.size, content: BackButtonStack(log: Log()))
            /// (a, r, g, b) of the premultiplied ARGB pixel at (x, y).
            func argb(_ x: Int, _ y: Int) -> SIMD4<Int> {
                let word = image.pixels[y * image.width + x]
                return SIMD4(Int(word >> 24), Int((word >> 16) & 0xFF), Int((word >> 8) & 0xFF), Int(word & 0xFF))
            }
            // The chevron's point, (6…9.54, 12) of its 24-point box: dark,
            // as `.primary` is in light, and grey, not blue.
            let point = argb(26, 22)
            #expect(point.x == 255)
            #expect(point.y < 60 && point.z < 60 && point.w < 60)
            #expect(abs(point.y - point.w) < 8)
            // Inside the angle, the bar's own background.
            #expect(argb(34, 22) != point)
        }

        /// A pop played out: its first frame, its end, and the frame after,
        /// which parks the screen it left.
        private func playMove(_ harness: Harness) async {
            await harness.settle(1.0 / 60)
            await harness.settle(0.6)
            await harness.settle(0.02)
        }

        @Test func aTapOnTheChevronPops() async {
            let log = Log()
            let harness = Harness(BackButtonStack(log: log), size: Self.size)
            await harness.tap(Self.underBar)
            #expect(log.take() == ["page 1"])
            await harness.tap(Self.chevron.center)
            await playMove(harness)
            await harness.tap(Self.underBar)
            #expect(log.take() == ["root"])
        }

        @Test func aTapAnywhereInItsSquarePops() async {
            let log = Log()
            let harness = Harness(BackButtonStack(log: log), size: Self.size)
            // Just past the square, on the title: still the pushed screen.
            await harness.tap(Point(x: 52, y: 22))
            await playMove(harness)
            await harness.tap(Self.underBar)
            #expect(log.take() == ["page 1"])
            // A corner of the square, well off the chevron's stroke.
            await harness.tap(Point(x: 14, y: 6))
            await playMove(harness)
            await harness.tap(Self.underBar)
            #expect(log.take() == ["root"])
        }
    }
}
