//
//  ShapeDrawingTests.swift
//  NucleantUITests
//
//  A shape view's path is made in the shape's own space, as SwiftUI hands
//  `path(in:)` a rect at the origin, and the command says where that space
//  lands: so the path depends on the shape and its size alone. A node
//  placed again at the same size draws the path it already made, and a
//  command moved into another space keeps its path as it is.
//

import Testing
@testable import NucleantUI

/// How many paths a `CountedShape` made.
@MainActor
final class PathCounter {
    var made = 0
}

@View
struct CountedShape: Shape {
    let counter: PathCounter

    func path(in rect: Rect) -> Path {
        counter.made += 1
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }
}

/// A counted shape whose width `knobs.unrelated` sets, beside a text that
/// `knobs.value` sets.
@View
struct ShapeBesideText {
    let knobs: Knobs
    let counter: PathCounter

    var body: some View {
        VStack(spacing: 0) {
            CountedShape(counter: counter)
                .frame(width: 40 + Double(knobs.unrelated), height: 20)
            Text("\(knobs.value)")
        }
    }
}

@MainActor
@Suite
struct ShapeDrawingTests {

    private func shapes<V: View>(_ view: V) -> [ShapeDraw] {
        OffscreenRender(environment: EnvironmentValues())
            .list(of: view, size: Size(width: 100, height: 100))
            .commands
            .compactMap { if case .shape(let draw) = $0 { draw } else { nil } }
    }

    @Test func aShapeViewsPathIsInItsOwnSpace() {
        let draws = shapes(Circle().fill(Color.red).frame(width: 20, height: 10).padding(5))
        #expect(draws.count == 1)
        guard let draw = draws.first else { return }
        #expect(draw.bounds == Rect(x: 0, y: 0, width: 20, height: 10), "its own rect, at the origin")
        #expect(draw.path == Circle().path(in: draw.bounds))
        #expect(draw.origin == Point(x: 40, y: 45), "centred in the 100 × 100 square")
        #expect(DrawCommand.shape(draw).paintBounds == Rect(x: 39, y: 44, width: 22, height: 12),
                "where it paints, out at its place: its rect and a pixel round it")
    }

    @Test func aMovedShapeKeepsItsPath() {
        guard let draw = shapes(Rectangle().fill(Color.red).frame(width: 20, height: 10)).first else {
            Issue.record("no shape")
            return
        }
        guard case .shape(let moved) = DrawCommand.shape(draw).translated(dx: 3, dy: -2) else { return }
        #expect(moved.path == draw.path)
        #expect(moved.bounds == draw.bounds)
        #expect(moved.origin == draw.origin.map { $0 + Point(x: 3, y: -2) })
    }

    @Test func aPathWithoutAnOriginIsMovedItself() {
        var path = Path()
        path.addRect(Rect(x: 10, y: 10, width: 5, height: 5))
        let draw = ShapeDraw(path: path, bounds: Rect(x: 10, y: 10, width: 5, height: 5), fill: .color(.red))
        guard case .shape(let moved) = DrawCommand.shape(draw).translated(dx: 3, dy: 4) else { return }
        #expect(moved.origin == nil)
        #expect(moved.bounds == Rect(x: 13, y: 14, width: 5, height: 5))
        #expect(moved.path == path.offsetBy(dx: 3, dy: 4))
        #expect(moved.pathBox == Rect(x: 13, y: 14, width: 5, height: 5), "the box moved with the path")
    }

    @Test func aShapeCarriesItsPathsBoxAndKeepsItWithThePath() {
        var path = Path()
        path.move(to: Point(x: 2, y: 3))
        path.addLine(to: Point(x: 12, y: -4))
        var draw = ShapeDraw(path: path, bounds: Rect(x: 0, y: 0, width: 4, height: 4), fill: .color(.red))
        #expect(draw.pathBox == path.boundingBox)
        #expect(DrawCommand.shape(draw).paintBounds == Rect(x: -1, y: -5, width: 14, height: 10),
                "the path's box and the bounds together, and a pixel round them")
        draw.path.addLine(to: Point(x: 20, y: 20))
        #expect(draw.pathBox == Rect(x: 2, y: -4, width: 18, height: 24), "a change of the path is a change of its box")
    }

    @Test func aShapeViewsCommandHasItsPathsBox() {
        guard let draw = shapes(Capsule().fill(Color.red).frame(width: 30, height: 10)).first else {
            Issue.record("no shape")
            return
        }
        #expect(draw.pathBox == draw.path.boundingBox)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ShapePathCacheTests {

        @Test func aShapePlacedAgainAtItsSizeDrawsThePathItMade() async {
            let knobs = Knobs()
            let counter = PathCounter()
            let harness = Harness(ShapeBesideText(knobs: knobs, counter: counter))
            #expect(counter.made == 1)

            await harness.change { knobs.value += 1 }
            #expect(counter.made == 1, "built again around it, placed again at its size")

            await harness.change { knobs.unrelated = 10 }
            #expect(counter.made == 2, "at another width, made again")
        }
    }
}
