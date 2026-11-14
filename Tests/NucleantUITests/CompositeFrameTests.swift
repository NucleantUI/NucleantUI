//
//  CompositeFrameTests.swift
//  NucleantUITests
//
//  Where a view the engine draws itself — a `Shader`, a `TextureView`, a
//  `ThorCanvas`, a `RenderTexture` — composites: its frame under the
//  transform it was placed under (`DrawContext.compositeFrame(of:)`), so it
//  moves with a stack's screen as the screen slides in and out, and shrinks
//  with it as it recedes under a zoom. And a `.shader` layer's commands
//  taken back to the frame's size under a scale
//  (`DisplayList.transformed(by:)`).
//
//  A window-less host has no engine to composite with, so a probe that lays
//  out as a `Shader` does records the frame instead.
//

import Observation
import Testing
@testable import NucleantUI

/// The frames a `FrameProbe` would have composited at, one per pass.
@MainActor
final class FrameLog {
    var frames: [Rect] = []
    var last: Rect? { frames.last }
}

/// Lays out as a `Shader` does — the space it is offered, no commands — and
/// records where its image would composite.
@View
struct FrameProbe {
    let log: FrameLog

    init(log: FrameLog, _viewID: ViewID = #viewID) {
        self.log = log
        self._viewID = _viewID
    }

    var body: Never { bodyUnavailable() }
}

extension FrameProbe: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        ContentNode(content: FrameProbeContent(log: log))
    }
}

struct FrameProbeContent: NodeContent {
    let log: FrameLog

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        log.frames.append(context.compositeFrame(of: rect))
    }
}

/// A probe on the root screen and one on the screen pushed over it, each
/// 40 points square at (20, 20) of its screen — by sliding, or by zooming
/// out of a square on the root screen.
@View
struct ProbedStack {
    @Bindable var pages: Pages
    let root: FrameLog
    let pushed: FrameLog
    let zooms: Bool
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $pages.path) {
            ZStack(alignment: .topLeading) {
                Color.red
                FrameProbe(log: root)
                    .frame(width: 40, height: 40)
                    .matchedTransitionSource(id: 1, in: zoom)
                    .offset(x: 20, y: 20)
            }
            .navigationTitle("Root")
            .navigationDestination(for: Int.self) { page in
                if zooms {
                    ProbedPage(log: pushed).navigationTransition(.zoom(sourceID: page, in: zoom))
                } else {
                    ProbedPage(log: pushed)
                }
            }
        }
    }
}

/// The screen `ProbedStack` pushes: blue, its probe where the root's is.
@View
struct ProbedPage {
    let log: FrameLog

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.blue
            FrameProbe(log: log)
                .frame(width: 40, height: 40)
                .offset(x: 20, y: 20)
        }
    }
}

@MainActor
struct CompositeFrameMath {

    private let rect = Rect(x: 10, y: 20, width: 40, height: 30)

    private func close(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9
            && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
    }

    private func frame(_ transform: Transform) -> Rect {
        var context = DrawContext()
        context.transform = transform
        return context.compositeFrame(of: rect)
    }

    @Test func withNoTransformItIsTheFrame() {
        #expect(DrawContext().compositeFrame(of: rect) == rect)
    }

    /// A slide or an `.offset`: the frame moved, and its size exactly what
    /// it was — the image is composited 1:1, not resampled.
    @Test func aMoveMovesItAndKeepsItsSizeExactly() {
        let moved = frame(.translation(x: 13.7, y: -2.25))
        #expect(moved.size == rect.size)
        #expect(close(moved, Rect(x: 23.7, y: 17.75, width: 40, height: 30)))
    }

    /// A zoom's receding screen or a `.scaleEffect`: the frame under it.
    @Test func aScaleScalesItAboutTheAnchor() {
        let scale = Transform.around(Point(x: 100, y: 100), .scale(x: 0.5, y: 0.8))
        #expect(close(frame(scale), rect.applying(scale)))
        #expect(close(frame(scale), Rect(x: 55, y: 36, width: 20, height: 24)))
    }

    /// The composite can't turn an image: under a rotation it goes where
    /// the frame's center goes, level and at its size.
    @Test func aRotationMovesItsCenterAndLeavesItLevel() {
        let turn = Transform.translation(x: 5, y: 0)
            .concatenating(.around(Point(x: rect.midX, y: rect.midY), .rotation(.degrees(30))))
        let shown = frame(turn)
        #expect(close(shown, rect.offsetBy(dx: 5, dy: 0)))
    }

    /// A flip shows the image the right way round, in the same place.
    @Test func aFlipKeepsThePlaceWithAPositiveSize() {
        let flip = Transform.around(Point(x: rect.midX, y: rect.midY), .scale(x: -1, y: 1))
        #expect(close(frame(flip), rect))
    }

    /// A `.shader` layer's commands under a scale, taken back about a
    /// corner: the transform applies after the command's own, and the clip,
    /// a rect on screen, scales with it.
    @Test func aListTransformedAppliesAfterEachCommandsOwn() {
        let shape = ShapeDraw(
            path: Path { $0.addRect(Rect(x: 0, y: 0, width: 10, height: 10)) },
            bounds: Rect(x: 0, y: 0, width: 10, height: 10),
            fill: .color(.red)
        )
        let state = DrawState(
            transform: .translation(x: 20, y: 0),
            clip: Rect(x: 20, y: 0, width: 5, height: 5),
            clipCornerRadius: 4
        )
        var list = DisplayList()
        list.append(.shape(shape), under: state)
        let back = Transform.around(Point(x: 100, y: 100), .scale(x: 0.5, y: 0.5))
        let transformed = list.transformed(by: back)
        #expect(transformed.commands == list.commands, "the geometry stays")
        let moved = transformed.state(at: 0)
        #expect(moved.transform == back.concatenating(state.transform))
        #expect(moved.clip == Rect(x: 60, y: 50, width: 2.5, height: 2.5))
        #expect(moved.clipCornerRadius == 2)
        #expect(transformed.paintBounds(at: 0) == Rect(x: 60, y: 50, width: 2.5, height: 2.5),
                "where it paints, worked out again under the new state")
        #expect(list.transformed(by: .identity) == list)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct CompositeFrameTests {

        /// A move under way: the frame after the change, on time, then
        /// `seconds` into it.
        private func into(_ harness: Harness, _ seconds: Double) async {
            await harness.settle(1.0 / 60)
            await harness.settle(seconds)
        }

        /// Played out, and the rebuild after it taken.
        private func played(_ harness: Harness) async {
            await harness.settle(0.6)
            await harness.settle(0.02)
        }

        @Test func aPushedScreensViewSlidesInWithIt() async throws {
            let pages = Pages(), root = FrameLog(), pushed = FrameLog()
            let harness = Harness(ProbedStack(pages: pages, root: root, pushed: pushed, zooms: false))
            let rootRest = try #require(root.last)

            pages.push(1)
            harness.host.update()
            await into(harness, 0.1)
            let sliding = try #require(pushed.last)
            let receding = try #require(root.last)

            await played(harness)
            let rest = try #require(pushed.last)
            #expect(rest == rootRest, "both screens' probes rest at the same place")

            // On its way in from the trailing edge: further along, same
            // height, same size.
            #expect(sliding.minX > rest.minX + 1)
            #expect(sliding.minX < rest.minX + 200)
            #expect(sliding.minY == rest.minY)
            #expect(sliding.size == rest.size)
            // The screen underneath moves the other way.
            #expect(receding.minX < rootRest.minX - 1)
            #expect(receding.size == rootRest.size)
        }

        @Test func aPoppedScreensViewSlidesOutWithIt() async throws {
            let pages = Pages(), root = FrameLog(), pushed = FrameLog()
            let harness = Harness(ProbedStack(pages: pages, root: root, pushed: pushed, zooms: false))
            pages.push(1)
            harness.host.update()
            await into(harness, 0)
            await played(harness)
            let rest = try #require(pushed.last)
            // Both screens' probes rest at the same place.
            let rootRest = rest

            pages.pop()
            harness.host.update()
            await into(harness, 0.1)
            let leaving = try #require(pushed.last)
            let returning = try #require(root.last)
            #expect(leaving.minX > rest.minX + 1, "on its way out to the trailing edge")
            #expect(leaving.minY == rest.minY)
            #expect(leaving.size == rest.size)
            #expect(returning.minX < rootRest.minX - 1, "the screen underneath coming back")

            await played(harness)
            let placedAfter = pushed.frames.count
            await harness.settle()
            #expect(pushed.frames.count == placedAfter, "let go once the pop is over")
            #expect(root.last == rootRest)
        }

        @Test func aZoomShrinksTheScreenUnderneathsViewWithIt() async throws {
            let pages = Pages(), root = FrameLog(), pushed = FrameLog()
            let harness = Harness(ProbedStack(pages: pages, root: root, pushed: pushed, zooms: true))
            let rest = try #require(root.last)

            pages.push(1)
            harness.host.update()
            await into(harness, 0.15)
            let receded = try #require(root.last)
            let growing = try #require(pushed.last)
            // Smaller, and drawn toward the screen's center.
            #expect(receded.width < rest.width - 0.5)
            #expect(abs(receded.width / receded.height - rest.width / rest.height) < 1e-9)
            #expect(receded.minX > rest.minX)
            // The pushed screen grows out of the square: its probe is
            // scaled down with it, not drawn at its full size.
            #expect(growing.width < 40)

            await played(harness)
            #expect(pushed.last?.size == Size(width: 40, height: 40))
        }
    }
}
