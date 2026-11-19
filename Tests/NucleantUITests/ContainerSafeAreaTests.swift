//
//  ContainerSafeAreaTests.swift
//  NucleantUITests
//
//  The window's edges as the `.container` safe area — on iOS the status
//  bar, the sensor housing and the home indicator: the root view laid out
//  inside them, the keyboard over the bottom one, `.ignoresSafeArea` by
//  region, a style background running on under them, and nothing reaching
//  out of a scroll view.
//

import Testing
@testable import NucleantUI

/// A full-window screen with a style background, reaching under `edges`.
@View
struct ColoredScreen {
    let edges: Edge.Set

    var body: some View {
        Text("Screen")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x3366CC), ignoresSafeAreaEdges: edges)
    }
}

/// A tall column in a scroll view filling the window, asking to ignore
/// every safe area.
@View
struct ScrolledIgnoring {
    let probe: SafeAreaProbe

    var body: some View {
        ScrollView {
            Color.gray.frame(height: 1000).probed("content", probe).ignoresSafeArea()
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ContainerSafeAreaTests {

        static let size = Size(width: 200, height: 400)
        /// A status bar's and a home indicator's worth.
        static let edges = EdgeInsets(top: 50, bottom: 30)

        /// Where the one shape drawn is: the style background.
        private func background(_ harness: Harness) throws -> Rect {
            let list = try #require(harness.host.windowContent)
            let rects = list.commands.compactMap { command -> Rect? in
                guard case .shape(let draw) = command else { return nil }
                let origin = draw.origin ?? .zero
                return draw.bounds.offsetBy(dx: origin.x, dy: origin.y)
            }
            return try #require(rects.max { $0.width * $0.height < $1.width * $1.height })
        }

        @Test func theRootIsLaidOutInsideTheWindowsEdges() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            await harness.settle()
            #expect(probe.frames["list"] == Rect(x: 0, y: 50, width: 200, height: 280))
            #expect(probe.frames["composer"] == Rect(x: 0, y: 330, width: 200, height: 40))
            #expect(probe.insets["list"] == EdgeInsets(top: 50))
            #expect(probe.insets["composer"] == EdgeInsets(bottom: 30))
        }

        /// The keyboard covers the home indicator too: the composer sits on
        /// the keyboard, not on the keyboard and the indicator stacked.
        @Test func theKeyboardCoversTheBottomEdge() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["composer"] == Rect(x: 0, y: 260, width: 200, height: 40))
            #expect(probe.insets["composer"] == EdgeInsets(bottom: 100))
        }

        /// A keyboard lower than the home indicator leaves the edge's inset.
        @Test func aKeyboardLowerThanTheBottomEdgeChangesNothing() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            harness.host.setKeyboardHeight(20, animation: nil)
            await harness.settle()
            #expect(probe.frames["composer"] == Rect(x: 0, y: 330, width: 200, height: 40))
        }

        @Test func ignoringEverythingReachesEveryEdge() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .all, edges: .all), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 400))
        }

        /// Under the keyboard, down to the home indicator, and not up into
        /// the status bar.
        @Test func ignoringTheKeyboardStopsAtTheWindowsEdges() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .keyboard, edges: .all), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["content"] == Rect(x: 0, y: 50, width: 200, height: 250))
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 50, width: 200, height: 320))
        }

        /// Up into the status bar, and not under the keyboard.
        @Test func ignoringTheWindowsEdgesStopsAtTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .container, edges: .all), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 300))

            harness.host.setKeyboardHeight(0, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 400))
        }

        @Test func aStyleBackgroundRunsUnderTheWindowsEdges() async throws {
            let harness = Harness(ColoredScreen(edges: .all), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            await harness.settle()
            #expect(try background(harness) == Rect(x: 0, y: 0, width: 200, height: 400))
        }

        @Test func aStyleBackgroundStaysInsideTheEdgesItDoesNotIgnore() async throws {
            let harness = Harness(ColoredScreen(edges: .top), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            await harness.settle()
            #expect(try background(harness) == Rect(x: 0, y: 0, width: 200, height: 370))
        }

        @Test func aStyleBackgroundStaysAboveTheKeyboard() async throws {
            let harness = Harness(ColoredScreen(edges: .all), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(try background(harness) == Rect(x: 0, y: 0, width: 200, height: 300))
        }

        @Test func nothingInAScrollViewReachesOut() async {
            let probe = SafeAreaProbe()
            let harness = Harness(ScrolledIgnoring(probe: probe), size: Self.size)
            harness.host.setSafeAreaInsets(Self.edges)
            await harness.settle()
            #expect(probe.frames["content"] == Rect(x: 0, y: 50, width: 200, height: 1000))
            #expect(probe.insets["content"] == EdgeInsets())
        }
    }
}
