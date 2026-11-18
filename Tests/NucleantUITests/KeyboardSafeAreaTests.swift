//
//  KeyboardSafeAreaTests.swift
//  NucleantUITests
//
//  The on-screen keyboard as the `.keyboard` safe area: the root view laid
//  out above it, `.ignoresSafeArea` reaching back under it, and
//  `GeometryProxy.safeAreaInsets` saying how far a view can reach.
//

import Testing
@testable import NucleantUI

/// Where the views of a test were placed, and the safe area insets they saw.
@MainActor
final class SafeAreaProbe {
    var frames: [String: Rect] = [:]
    var insets: [String: EdgeInsets] = [:]
    var readerBuilds = 0
}

extension View {
    /// Notes the view's frame in the window under `name`, and its safe area
    /// insets.
    func probed(_ name: String, _ probe: SafeAreaProbe) -> some View {
        self
            .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { probe.frames[name] = $0 }
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { probe.insets[name] = $0 }
    }
}

/// A list filling the window over a 40-point composer at the bottom, as a
/// chat thread is.
@View
struct KeyboardColumn {
    let probe: SafeAreaProbe

    var body: some View {
        VStack(spacing: 0) {
            Color.blue.probed("list", probe)
            Color.red.frame(height: 40).probed("composer", probe)
        }
    }
}

/// A backdrop behind the content, ignoring `regions` at `edges`: what it
/// wraps is what reaches out, so that is what is measured.
@View
struct KeyboardBackdrop {
    let probe: SafeAreaProbe
    let regions: SafeAreaRegions
    let edges: Edge.Set

    var body: some View {
        ZStack {
            Color.gray.probed("backdrop", probe).ignoresSafeArea(regions, edges: edges)
            Color.blue.probed("content", probe)
        }
    }
}

/// A 60-point square in the top leading corner, nowhere near the keyboard.
@View
struct KeyboardFarAway {
    let probe: SafeAreaProbe

    var body: some View {
        Color.green.frame(width: 60, height: 60).probed("square", probe)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A reader filling the window, its content built from the bottom inset.
@View
struct KeyboardReader {
    let probe: SafeAreaProbe

    var body: some View {
        GeometryReader { proxy in
            let _ = probe.readerBuilds += 1
            Color.clear.probed("reader", probe)
                .overlay(Text("\(Int(proxy.safeAreaInsets.bottom))"))
                .onAppear { probe.insets["proxy"] = proxy.safeAreaInsets }
                .onChange(of: proxy.safeAreaInsets) { _, insets in probe.insets["proxy"] = insets }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct KeyboardSafeAreaTests {

        static let size = Size(width: 200, height: 400)

        @Test func theRootIsLaidOutAboveTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)
            #expect(probe.frames["composer"] == Rect(x: 0, y: 360, width: 200, height: 40))

            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["list"] == Rect(x: 0, y: 0, width: 200, height: 260))
            #expect(probe.frames["composer"] == Rect(x: 0, y: 260, width: 200, height: 40))

            harness.host.setKeyboardHeight(0, animation: nil)
            await harness.settle()
            #expect(probe.frames["composer"] == Rect(x: 0, y: 360, width: 200, height: 40))
        }

        /// The view on the keyboard sees it under itself; the one above it
        /// does not, at its bottom edge.
        @Test func aViewOnTheKeyboardHasItsHeightAsItsBottomInset() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)
            #expect(probe.insets["composer"] == EdgeInsets())

            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.insets["composer"] == EdgeInsets(bottom: 100))
            #expect(probe.insets["list"] == EdgeInsets())
        }

        @Test func aViewNowhereNearTheKeyboardHasNoInsets() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardFarAway(probe: probe), size: Self.size)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["square"] == Rect(x: 0, y: 0, width: 60, height: 60))
            #expect(probe.insets["square"] == EdgeInsets())
        }

        @Test func aViewIgnoringTheKeyboardGoesUnderIt() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .keyboard, edges: .all), size: Self.size)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 400))
            #expect(probe.frames["content"] == Rect(x: 0, y: 0, width: 200, height: 300))
            // Out at the window's edge, there is nothing further to reach.
            #expect(probe.insets["backdrop"] == EdgeInsets())
        }

        @Test func ignoringAllRegionsGoesUnderTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .all, edges: .all), size: Self.size)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 400))
        }

        @Test func ignoringAnotherRegionStaysAboveTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .container, edges: .all), size: Self.size)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 300))
        }

        @Test func ignoringOtherEdgesStaysAboveTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardBackdrop(probe: probe, regions: .keyboard, edges: [.top, .horizontal]), size: Self.size)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()
            #expect(probe.frames["backdrop"] == Rect(x: 0, y: 0, width: 200, height: 300))
        }

        /// A reader whose content asked for the insets builds it again when
        /// they change.
        @Test func aReaderAskingForTheInsetsIsBuiltAgainForTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardReader(probe: probe), size: Self.size)
            await harness.settle()
            #expect(probe.insets["proxy"] == EdgeInsets())
            let builds = probe.readerBuilds

            harness.host.setKeyboardHeight(120, animation: nil)
            await harness.settle()
            #expect(probe.insets["proxy"] == EdgeInsets(bottom: 120))
            #expect(probe.readerBuilds > builds)

            harness.host.setKeyboardHeight(0, animation: nil)
            await harness.settle()
            #expect(probe.insets["proxy"] == EdgeInsets())
        }

        /// The keyboard stays where it is, at the window's bottom edge, as
        /// the window changes size.
        @Test func aResizedWindowKeepsTheKeyboard() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)
            harness.host.setKeyboardHeight(100, animation: nil)
            await harness.settle()

            harness.host.setSize(Size(width: 300, height: 500))
            await harness.settle()
            #expect(probe.frames["composer"] == Rect(x: 0, y: 360, width: 300, height: 40))
        }

        /// The views move with the keyboard's animation, frame after frame,
        /// and jump without one.
        @Test func theViewsMoveWithTheKeyboardsAnimation() async {
            let probe = SafeAreaProbe()
            let harness = Harness(KeyboardColumn(probe: probe), size: Self.size)

            harness.host.setKeyboardHeight(100, animation: nil)
            harness.host.update()
            harness.host.update()
            #expect(!harness.host.didRunPass, "there at once")

            harness.host.setKeyboardHeight(0, animation: .linear(duration: 0.5))
            harness.host.update()
            await harness.settle(0.05)
            #expect(harness.host.didRunPass, "still moving")
        }
    }
}
