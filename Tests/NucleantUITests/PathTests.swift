//
//  PathTests.swift
//  NucleantUITests
//
//  The SwiftUI `Path` API beyond the basic elements: curves, arcs,
//  transforms and measuring.
//

import Foundation
import Testing
@testable import NucleantUI

@Suite struct PathTests {
    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
        abs(a - b) <= tolerance
    }

    private func near(_ a: Point?, _ b: Point, _ tolerance: Double = 1e-6) -> Bool {
        guard let a else { return false }
        return near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance)
    }

    @Test func currentPointFollowsTheLastSegment() {
        var path = Path()
        #expect(path.currentPoint == nil)
        path.move(to: Point(x: 1, y: 2))
        #expect(path.currentPoint == Point(x: 1, y: 2))
        path.addQuadCurve(to: Point(x: 5, y: 6), control: Point(x: 3, y: 0))
        #expect(path.currentPoint == Point(x: 5, y: 6))
        path.closeSubpath()
        #expect(path.currentPoint == Point(x: 1, y: 2))
    }

    @Test func addLinesMakesAPolyline() {
        var path = Path()
        path.addLines([Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)])
        #expect(path.elements == [
            .move(Point(x: 0, y: 0)), .line(Point(x: 10, y: 0)), .line(Point(x: 10, y: 10)),
        ])
    }

    @Test func boundingRectIsTheCurveNotItsControlPoints() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addQuadCurve(to: Point(x: 10, y: 0), control: Point(x: 5, y: 10))
        let box = path.boundingRect
        #expect(near(box.minX, 0) && near(box.maxX, 10))
        // A quadratic reaches half way to its control point.
        #expect(near(box.maxY, 5, 0.01))
        #expect(Path().boundingRect.width == 0)
    }

    @Test func quarterArcEndsOnTheCircle() {
        var path = Path()
        path.addRelativeArc(center: Point(x: 10, y: 10), radius: 5, startAngle: .degrees(0), delta: .degrees(90))
        // Increasing angles run clockwise on screen: from the right, to the bottom.
        #expect(near(path.currentPoint, Point(x: 10, y: 15)))
        #expect(path.elements.first == .move(Point(x: 15, y: 10)))
    }

    @Test func arcCoversTheWholeSweep() {
        var path = Path()
        path.addArc(center: .zero, radius: 10, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: false)
        #expect(near(path.currentPoint, Point(x: 0, y: -10), 1e-9))
        let box = path.boundingRect
        #expect(near(box.maxX, 10, 1e-3) && near(box.maxY, 10, 1e-3))
        #expect(near(box.minX, -10, 1e-3) && near(box.minY, -10, 1e-3))
    }

    @Test func clockwiseArcRunsThroughDecreasingAngles() {
        var path = Path()
        path.addArc(center: .zero, radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: true)
        // The long way round: 0° back through 270° to 90°.
        let box = path.boundingRect
        #expect(near(box.minY, -10, 1e-3))
        #expect(near(box.minX, -10, 1e-3))
        #expect(near(path.currentPoint, Point(x: 0, y: 10), 1e-9))
    }

    @Test func arcJoinsTheCurrentPointWithALine() {
        var path = Path()
        path.move(to: Point(x: -20, y: 0))
        path.addArc(center: .zero, radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        #expect(path.elements[1] == .line(Point(x: 10, y: 0)))
    }

    @Test func tangentArcRoundsTheCorner() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addArc(tangent1End: Point(x: 100, y: 0), tangent2End: Point(x: 100, y: 100), radius: 20)
        // It leaves the first line 20 short of the corner and ends 20 along the second.
        #expect(path.elements[1] == .line(Point(x: 80, y: 0)))
        #expect(near(path.currentPoint, Point(x: 100, y: 20), 1e-9))
        #expect(path.boundingRect.maxX <= 100 + 1e-9)
    }

    @Test func collinearTangentArcIsALine() {
        var path = Path()
        path.move(to: .zero)
        path.addArc(tangent1End: Point(x: 10, y: 0), tangent2End: Point(x: 20, y: 0), radius: 5)
        #expect(path.elements == [.move(.zero), .line(Point(x: 10, y: 0))])
    }

    @Test func translationKeepsRectsAsRects() {
        let moved = Path(Rect(x: 0, y: 0, width: 10, height: 10)).applying(.translation(x: 5, y: 6))
        #expect(moved.elements == [.rect(Rect(x: 5, y: 6, width: 10, height: 10), radiusX: 0, radiusY: 0)])
    }

    @Test func rotationExpandsRectsToLines() {
        let turned = Path(Rect(x: 0, y: 0, width: 10, height: 10)).applying(.rotation(.degrees(90)))
        #expect(turned.elements.count == 5)
        let box = turned.boundingRect
        #expect(near(box.minX, -10, 1e-9) && near(box.maxX, 0, 1e-9))
        #expect(near(box.minY, 0, 1e-9) && near(box.maxY, 10, 1e-9))
    }

    @Test func rotatedEllipseKeepsItsExtent() {
        let turned = Path(ellipseIn: Rect(x: -20, y: -10, width: 40, height: 20)).applying(.rotation(.degrees(90)))
        let box = turned.boundingRect
        #expect(near(box.width, 20, 0.05) && near(box.height, 40, 0.05))
    }

    @Test func addPathAppliesTheTransform() {
        var path = Path()
        path.addRect(Rect(x: 0, y: 0, width: 4, height: 4), transform: .scale(x: 2, y: 2))
        #expect(path.elements == [.rect(Rect(x: 0, y: 0, width: 8, height: 8), radiusX: 0, radiusY: 0)])
    }

    @Test func roundedRectInitKeepsTheCornerSize() {
        let path = Path(roundedRect: Rect(x: 0, y: 0, width: 20, height: 10), cornerSize: Size(width: 4, height: 2))
        #expect(path.elements == [.rect(Rect(x: 0, y: 0, width: 20, height: 10), radiusX: 4, radiusY: 2)])
    }

    @Test func containsFollowsACurve() {
        var path = Path()
        path.move(to: Point(x: 0, y: 10))
        path.addQuadCurve(to: Point(x: 10, y: 10), control: Point(x: 5, y: -10))
        path.closeSubpath()
        #expect(path.contains(Point(x: 5, y: 8)))
        #expect(!path.contains(Point(x: 5, y: 0)))
    }

    @Test func forEachVisitsInOrder() {
        var seen: [Path.Element] = []
        Path { $0.addLines([Point(x: 0, y: 0), Point(x: 1, y: 1)]) }.forEach { seen.append($0) }
        #expect(seen == [.move(Point(x: 0, y: 0)), .line(Point(x: 1, y: 1))])
    }
}

@Suite struct PathTextAndImageTests {
    private let image = RasterImage(width: 2, height: 2, pixels: [0xFFFF0000, 0xFFFF0000, 0xFFFF0000, 0xFFFF0000])

    @Test func addTextAndImageAreElements() {
        var path = Path()
        path.addText("Hi", at: Point(x: 3, y: 4), font: .system(size: 12))
        path.addImage(image, in: Rect(x: 1, y: 2, width: 10, height: 10))
        #expect(path.elements == [
            .text("Hi", origin: Point(x: 3, y: 4), font: .system(size: 12)),
            .image(image, in: Rect(x: 1, y: 2, width: 10, height: 10)),
        ])
    }

    @Test func offsetMovesBoth() {
        var path = Path()
        path.addText("Hi", at: Point(x: 3, y: 4), font: .system(size: 12))
        path.addImage(image, in: Rect(x: 1, y: 2, width: 10, height: 10))
        let moved = path.offsetBy(dx: 10, dy: 20)
        #expect(moved.elements == [
            .text("Hi", origin: Point(x: 13, y: 24), font: .system(size: 12)),
            .image(image, in: Rect(x: 11, y: 22, width: 10, height: 10)),
        ])
    }

    @Test func applyingScalesTextAndMapsTheImage() {
        var path = Path()
        path.addText("Hi", at: Point(x: 3, y: 4), font: .system(size: 10))
        path.addImage(image, in: Rect(x: 1, y: 2, width: 10, height: 10))
        let scaled = path.applying(.scale(x: 2, y: 2))
        #expect(scaled.elements == [
            .text("Hi", origin: Point(x: 6, y: 8), font: .system(size: 20)),
            .image(image, in: Rect(x: 2, y: 4, width: 20, height: 20)),
        ])
    }

    @Test func boundsCoverTheImageAndTheText() {
        var path = Path()
        path.addImage(image, in: Rect(x: 5, y: 5, width: 10, height: 10))
        #expect(path.boundingRect == Rect(x: 5, y: 5, width: 10, height: 10))
        path.addText("Hello", at: Point(x: 40, y: 40), font: .system(size: 10))
        let box = path.boundingRect
        #expect(box.maxX >= 40 + 5 * 6 && box.maxY >= 40 + 10)
    }

    @Test func imageCountsForContainment() {
        var path = Path()
        path.addImage(image, in: Rect(x: 0, y: 0, width: 10, height: 10))
        #expect(path.contains(Point(x: 5, y: 5)))
        #expect(!path.contains(Point(x: 15, y: 5)))
    }
}
