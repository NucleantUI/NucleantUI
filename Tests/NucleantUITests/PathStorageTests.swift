//
//  PathStorageTests.swift
//  NucleantUITests
//
//  A path keeps a byte per element and the points of all of them in one
//  array, its texts and images in a list of their own — and gives back the
//  elements it was made of.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct PathStorageTests {

    private let image = RasterImage(width: 2, height: 2, pixels: [UInt32](repeating: 0xFFFF_FFFF, count: 4))

    private var everyKind: [Path.Element] {
        [
            .move(Point(x: 1, y: 2)),
            .line(Point(x: 3, y: 4)),
            .quad(control: Point(x: 5, y: 6), end: Point(x: 7, y: 8)),
            .cubic(control1: Point(x: 9, y: 10), control2: Point(x: 11, y: 12), end: Point(x: 13, y: 14)),
            .close,
            .text("Hi", origin: Point(x: 20, y: 30), font: .system(size: 12)),
            .rect(Rect(x: 40, y: 50, width: 60, height: 70), radiusX: 4, radiusY: 2),
            .image(image, in: Rect(x: 0, y: 0, width: 8, height: 8)),
            .ellipse(center: Point(x: 100, y: 100), radiusX: 10, radiusY: 5),
        ]
    }

    @Test func theElementsComeBackAsTheyWentIn() {
        var path = Path()
        for element in everyKind { path.append(element) }
        #expect(path.elements == everyKind)

        var set = Path()
        set.elements = everyKind
        #expect(set == path, "set as elements or built one by one, the same path")
        #expect(set.hashValue == path.hashValue)
        #expect(Array(path.elementSequence) == everyKind)
    }

    @Test func anElementIsAByteAndItsPoints() {
        var path = Path()
        for element in everyKind { path.append(element) }
        #expect(path.verbs == [.move, .line, .quad, .cubic, .close, .embedded, .rect, .embedded, .ellipse])
        // 1 + 1 + 2 + 3 for the lines and curves, 3 for the rect (origin,
        // size, radii), 2 for the ellipse (center, radii).
        #expect(path.points.count == 12)
        #expect(path.embedded == [
            .text("Hi", origin: Point(x: 20, y: 30), font: .system(size: 12)),
            .image(image, in: Rect(x: 0, y: 0, width: 8, height: 8)),
        ], "the texts and images in the order they were added")
    }

    @Test func movingAPathMovesItsPositionsOnly() {
        var path = Path()
        for element in everyKind { path.append(element) }
        let moved = path.offsetBy(dx: 1, dy: -1)
        let shift = Point(x: 1, y: -1)
        #expect(moved.elements == [
            .move(Point(x: 1, y: 2) + shift),
            .line(Point(x: 3, y: 4) + shift),
            .quad(control: Point(x: 5, y: 6) + shift, end: Point(x: 7, y: 8) + shift),
            .cubic(control1: Point(x: 9, y: 10) + shift, control2: Point(x: 11, y: 12) + shift, end: Point(x: 13, y: 14) + shift),
            .close,
            .text("Hi", origin: Point(x: 20, y: 30) + shift, font: .system(size: 12)),
            .rect(Rect(x: 41, y: 49, width: 60, height: 70), radiusX: 4, radiusY: 2),
            .image(image, in: Rect(x: 1, y: -1, width: 8, height: 8)),
            .ellipse(center: Point(x: 101, y: 99), radiusX: 10, radiusY: 5),
        ], "a rect keeps its size and corners, an ellipse its radii")
        #expect(path.offsetBy(dx: 0, dy: 0) == path)
    }

    @Test func theBoxCoversEveryKindOfElement() {
        let rect = Path { $0.addRoundedRect(Rect(x: 10, y: 20, width: 30, height: 40), radiusX: 5, radiusY: 5) }
        #expect(rect.boundingBox == Rect(x: 10, y: 20, width: 30, height: 40), "the rect, not its radii")
        let ellipse = Path { $0.addEllipse(in: Rect(x: 0, y: 0, width: 20, height: 10)) }
        #expect(ellipse.boundingBox == Rect(x: 0, y: 0, width: 20, height: 10))
        var both = rect
        both.addImage(image, in: Rect(x: -5, y: -5, width: 5, height: 5))
        #expect(both.boundingBox == Rect(x: -5, y: -5, width: 45, height: 65))
        #expect(Path().boundingBox == nil)
    }

    @Test func aPathOfOneElementSaysWhichItIs() {
        let rect = Path(Rect(x: 0, y: 0, width: 4, height: 4))
        #expect(rect.soleElement == .rect(Rect(x: 0, y: 0, width: 4, height: 4), radiusX: 0, radiusY: 0))
        #expect(Path { $0.addLines([.zero, Point(x: 1, y: 1)]) }.soleElement == nil)
        #expect(Path().soleElement == nil)
    }

    @Test func pathsAppendedKeepTheirOrder() {
        var first = Path { $0.addText("A", at: .zero, font: .system(size: 10)) }
        first.move(to: Point(x: 1, y: 1))
        let second = Path {
            $0.addImage(image, in: Rect(x: 0, y: 0, width: 1, height: 1))
            $0.addLine(to: Point(x: 2, y: 2))
        }
        first.addPath(second)
        #expect(first.elements == [
            .text("A", origin: .zero, font: .system(size: 10)),
            .move(Point(x: 1, y: 1)),
            .image(image, in: Rect(x: 0, y: 0, width: 1, height: 1)),
            .line(Point(x: 2, y: 2)),
        ])
    }
}
