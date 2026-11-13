//
//  NavigationTransitionTests.swift
//  NucleantUITests
//
//  A `NavigationStack` playing its pushes and pops: `.automatic` sliding
//  the new screen in over the old, `.zoom` growing it out of its source,
//  both screens drawn while the move plays and the popped one let go after
//  it — read off the pixels drawn, frame after frame as a display draws
//  them. And `@Namespace`: one identity per view, kept while it stands.
//

import Observation
import Testing
@testable import NucleantUI

/// The pages a test stack shows, changed by the tests.
@MainActor
@Observable
final class Pages {
    var path: [Int] = []

    func push(_ page: Int) { path.append(page) }
    func pop() { path.removeLast() }
}

/// Red underneath, blue pushed over it — by sliding, or by zooming out of
/// a green square on the red screen.
@View
struct PagedStack {
    @Bindable var pages: Pages
    let zooms: Bool
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $pages.path) {
            ZStack(alignment: .topLeading) {
                Color.red
                Color.green
                    .frame(width: 40, height: 40)
                    .matchedTransitionSource(id: 1, in: zoom)
                    .offset(x: 20, y: 60)
            }
            // Titled, so the root keeps its bar and its screen the same
            // place as the screens pushed on it.
            .navigationTitle("Pages")
            .navigationDestination(for: Int.self) { page in
                if zooms {
                    Color.blue.navigationTransition(.zoom(sourceID: page, in: zoom))
                } else {
                    Color.blue
                }
            }
        }
    }
}

/// Reports its namespace every time it is built.
@View
struct NamespaceReporter {
    let log: Log
    /// Changed by the test, so the reporter is built again.
    let count: Int
    @Namespace private var space

    var body: some View {
        let _ = log("\(space.hashValue)")
        Text("\(count)")
    }
}

/// Two reporters, rebuilt with a count.
@View
struct TwoNamespaces {
    let log: Log
    let stage: Stage

    var body: some View {
        VStack {
            NamespaceReporter(log: log, count: stage.items.count)
            NamespaceReporter(log: log, count: stage.items.count)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct NavigationTransitionTests {

        private func isRed(_ p: SIMD4<UInt8>) -> Bool { p.x > 120 && p.z < 120 }
        private func isBlue(_ p: SIMD4<UInt8>) -> Bool { p.z > 120 && p.x < 80 }

        /// A move under way: the frame after the change, on time, then
        /// `seconds` into it.
        private func into(_ painted: PaintedHarness, _ seconds: Double) async {
            await painted.nextFrame()
            await painted.settle(seconds)
        }

        /// Played out, and the rebuild after it taken.
        private func played(_ painted: PaintedHarness) async {
            await painted.settle(0.6)
            await painted.settle(0.02)
        }

        @Test func anAutomaticPushSlidesTheNewScreenIn() async {
            let pages = Pages()
            let painted = PaintedHarness(PagedStack(pages: pages, zooms: false))
            #expect(isRed(painted.pixel(10, 150)))

            pages.push(1)
            painted.update()
            await into(painted, 0.1)
            // On its way in from the trailing edge, over the old screen.
            #expect(isBlue(painted.pixel(190, 150)))
            #expect(isRed(painted.pixel(10, 150)))

            await played(painted)
            #expect(isBlue(painted.pixel(10, 150)))
            #expect(isBlue(painted.pixel(190, 150)))
        }

        @Test func aPopPlaysThenLetsTheScreenGo() async {
            let pages = Pages()
            let painted = PaintedHarness(PagedStack(pages: pages, zooms: false))
            pages.push(1)
            painted.update()
            await into(painted, 0)
            await played(painted)
            #expect(isBlue(painted.pixel(10, 150)))

            pages.pop()
            painted.update()
            await into(painted, 0.1)
            // Still drawn, sliding back out over the screen underneath.
            #expect(isBlue(painted.pixel(190, 150)))
            #expect(isRed(painted.pixel(10, 150)))

            await played(painted)
            #expect(isRed(painted.pixel(190, 150)))
            #expect(isRed(painted.pixel(10, 150)))
        }

        @Test func aZoomGrowsOutOfItsSource() async {
            let pages = Pages()
            let painted = PaintedHarness(PagedStack(pages: pages, zooms: true))
            // The source square, drawn: green, somewhere down x = 40.
            let sourceY = (0..<200).first { y in
                let p = painted.pixel(40, y)
                return p.y > 120 && p.x < 120 && p.z < 160
            }
            guard let sourceY else {
                Issue.record("no source drawn")
                return
            }

            pages.push(1)
            painted.update()
            await painted.nextFrame()
            // Just begun: the new screen over the source, not yet out to
            // the far corner.
            #expect(isBlue(painted.pixel(40, sourceY + 2)))
            #expect(!isBlue(painted.pixel(190, 190)))

            await played(painted)
            #expect(isBlue(painted.pixel(190, 190)))
            #expect(isBlue(painted.pixel(10, 150)))
        }

        @Test func aPushThatAsksForNoAnimationIsThereAtOnce() async {
            let pages = Pages()
            let painted = PaintedHarness(PagedStack(pages: pages, zooms: false))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { pages.push(1) }
            painted.update()
            #expect(isBlue(painted.pixel(10, 150)))
            await painted.settle(0.02)
            #expect(isBlue(painted.pixel(10, 150)))
        }

        @Test func aNamespaceIsTheViewsOwnForAsLongAsItStands() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(TwoNamespaces(log: log, stage: stage))
            let first = log.take()
            #expect(first.count == 2)
            #expect(first[0] != first[1], "two views, two namespaces")

            stage.add(1)
            await harness.settle()
            #expect(log.take() == first, "rebuilt: the same namespaces")
        }
    }
}

/// Red underneath, blue pushed over it through a shader.
@View
struct ShaderPagedStack {
    @Bindable var pages: Pages

    var body: some View {
        NavigationStack(path: $pages.path) {
            Color.red
                // Titled, so the root keeps its bar and its screen the same
                // place as the screen pushed on it.
                .navigationTitle("Pages")
                .navigationDestination(for: Int.self) { _ in
                    Color.blue.navigationTransition(.shader(
                        ShaderFunction("fragColor = layer(uv) * progress;"),
                        timing: .smooth(duration: 0.4)
                    ))
                }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ShaderNavigationTransitionTests {

        private func isRed(_ p: SIMD4<UInt8>) -> Bool { p.x > 120 && p.z < 120 }
        private func isBlue(_ p: SIMD4<UInt8>) -> Bool { p.z > 120 && p.x < 80 }

        // A window-less host runs no shaders: the screen a shader move draws
        // through one is drawn as it is — in place, where `.automatic`
        // would have it slid aside.

        @Test func aShaderPushDrawsTheNewScreenInPlace() async {
            let pages = Pages()
            let painted = PaintedHarness(ShaderPagedStack(pages: pages))
            pages.push(1)
            painted.update()
            await painted.nextFrame()
            await painted.settle(0.1)
            #expect(isBlue(painted.pixel(10, 150)))
            #expect(isBlue(painted.pixel(190, 150)))
        }

        @Test func aShaderPopKeepsTheScreenUntilItHasPlayed() async {
            let pages = Pages()
            let painted = PaintedHarness(ShaderPagedStack(pages: pages))
            pages.push(1)
            painted.update()
            await painted.nextFrame()
            await painted.settle(0.6)
            await painted.settle(0.02)

            pages.pop()
            painted.update()
            await painted.nextFrame()
            await painted.settle(0.1)
            // Still there, in place, while its pop plays.
            #expect(isBlue(painted.pixel(10, 150)))

            await painted.settle(0.6)
            await painted.settle(0.02)
            #expect(isRed(painted.pixel(10, 150)))
        }
    }
}
