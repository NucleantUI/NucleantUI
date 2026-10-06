//
//  CanvasPaintTests.swift
//  NucleantUITests
//
//  `CanvasPaint`: `Path` instructions on a ThorVG shape, read back through
//  the shape's own path.
//

import Testing
import NucleantThorVG
@testable import NucleantUI

@Suite struct CanvasPaintTests {
    private func points(_ paint: CanvasPaint) -> [Point] {
        paint.get_path().pts.map { Point(x: Double($0.x), y: Double($0.y)) }
    }

    private func near(_ a: Point?, _ b: Point, _ tolerance: Double = 1e-4) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    @Test func linesAndCurvesCarryOver() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 10, y: 0))
        path.addCurve(to: Point(x: 20, y: 10), control1: Point(x: 15, y: 0), control2: Point(x: 20, y: 5))
        let paint = CanvasPaint(path)
        #expect(points(paint) == [
            Point(x: 0, y: 0), Point(x: 10, y: 0),
            Point(x: 15, y: 0), Point(x: 20, y: 5), Point(x: 20, y: 10),
        ])
    }

    @Test func quadBecomesTheCubicThroughTheSameCurve() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addQuadCurve(to: Point(x: 30, y: 0), control: Point(x: 15, y: 30))
        let pts = points(CanvasPaint(path))
        #expect(pts.count == 4)
        #expect(near(pts[1], Point(x: 10, y: 20)))
        #expect(near(pts[2], Point(x: 20, y: 20)))
        #expect(near(pts[3], Point(x: 30, y: 0)))
    }

    @Test func quadToStartsWhereThePenIs() {
        let paint = CanvasPaint()
        _ = paint.move_to(x: 0, y: 0)
        paint.quad_to(control: Point(x: 15, y: 30), to: Point(x: 30, y: 0))
        #expect(near(points(paint)[1], Point(x: 10, y: 20)))
    }

    @Test func arcEndsOnTheCircle() {
        let paint = CanvasPaint()
        _ = paint.move_to(x: 15, y: 10)
        paint.append_relative_arc(center: Point(x: 10, y: 10), radius: 5, startAngle: .degrees(0), delta: .degrees(90))
        #expect(near(paint.currentPoint, Point(x: 10, y: 15)))
    }

    @Test func tangentArcRoundsTheCorner() {
        let paint = CanvasPaint()
        _ = paint.move_to(x: 0, y: 0)
        paint.append_arc(tangent1End: Point(x: 100, y: 0), tangent2End: Point(x: 100, y: 100), radius: 20)
        #expect(near(paint.currentPoint, Point(x: 100, y: 20)))
    }

    @Test func transformIsApplied() {
        let paint = CanvasPaint()
        paint.append(Path { $0.addLines([Point(x: 0, y: 0), Point(x: 10, y: 0)]) }, transform: .translation(x: 5, y: 7))
        #expect(points(paint) == [Point(x: 5, y: 7), Point(x: 15, y: 7)])
    }
}
