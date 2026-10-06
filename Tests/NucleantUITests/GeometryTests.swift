//
//  GeometryTests.swift
//  NucleantUITests
//
//  `Point` and `Size` are `SIMD2<Double>`, and `Rect`'s operations are
//  packed vector math on them. `width`/`height` must be the `x`/`y` lanes,
//  and every operation must give bit for bit what the per-field scalar
//  formula gives, signed zeros, infinities and NaNs included.
//

import Testing
@testable import NucleantUI

/// Origins and extents covering signs, zero of both signs, non-finite values.
private let starts: [Double] = [-2, -0.0, 1.5, .infinity, .nan]
private let extents: [Double] = [-1, 0, 2.5, .infinity, .nan]

private let rects: [Rect] = starts.flatMap { x in
    starts.flatMap { y in
        extents.flatMap { width in
            extents.map { height in Rect(x: x, y: y, width: width, height: height) }
        }
    }
}

/// Whether `rect` holds exactly these four values, comparing bit patterns so
/// `-0.0` and NaN are checked too.
private func holds(_ rect: Rect, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Bool {
    rect.x.bitPattern == x.bitPattern && rect.y.bitPattern == y.bitPattern
        && rect.width.bitPattern == width.bitPattern && rect.height.bitPattern == height.bitPattern
}

@Suite
struct GeometryTests {

    @Test func widthAndHeightAreTheXAndYLanes() {
        var size = Size(width: 3, height: 4)
        #expect(size == SIMD2(3, 4))
        #expect((size.x, size.y) == (3, 4))
        size.height = 7
        size[.horizontal] = 9
        #expect(size == SIMD2(9, 7))
        #expect((size[.horizontal], size[.vertical]) == (9, 7))

        var point = Point(x: 1, y: 2)
        point[.vertical] += 3
        #expect(point == SIMD2(1, 5))
        #expect(point + size == Point(x: 10, y: 12))
    }

    @Test func signedZerosStayEqualAndHashAlike() {
        #expect(Point(x: -0.0, y: 0) == Point(x: 0, y: -0.0))
        #expect(Point(x: -0.0, y: 0).hashValue == Point(x: 0, y: -0.0).hashValue)
        #expect(Rect(x: -0.0, y: 0, width: 1, height: 1) == Rect(x: 0, y: 0, width: 1, height: 1))
        #expect(Point(x: .nan, y: 0) != Point(x: .nan, y: 0))
    }

    @Test func centerAndAnchorsMatchTheScalarFormulas() {
        let units = [UnitPoint.topLeading, .center, .bottomTrailing, UnitPoint(x: 0.3, y: -1.5)]
        for rect in rects {
            #expect(holds(Rect(origin: rect.center, size: .zero), rect.midX, rect.midY, 0, 0))
            for unit in units {
                let point = unit.resolved(in: rect)
                let x = rect.minX + rect.width * unit.x
                let y = rect.minY + rect.height * unit.y
                #expect(point.x.bitPattern == x.bitPattern && point.y.bitPattern == y.bitPattern)
            }
        }
    }

    @Test func containsPointMatchesTheScalarFormula() {
        let coordinates: [Double] = [-2, -0.0, 0, 1.5, 3, .infinity, .nan]
        for rect in rects {
            for x in coordinates {
                for y in coordinates {
                    let expected = x >= rect.minX && x < rect.maxX && y >= rect.minY && y < rect.maxY
                    #expect(rect.contains(Point(x: x, y: y)) == expected)
                }
            }
        }
    }

    @Test func offsetAndExpandMatchTheScalarFormulas() {
        for rect in rects {
            for d in [-1.25, 0, 4, .infinity] {
                let moved = rect.offsetBy(dx: d, dy: -d)
                #expect(holds(moved, rect.x + d, rect.y + -d, rect.width, rect.height))
                let grown = rect.expanded(by: d)
                #expect(holds(grown, rect.minX - d, rect.minY - d, rect.width + 2 * d, rect.height + 2 * d))
            }
        }
    }

    @Test func insetMatchesTheScalarFormula() {
        let amounts: [Double] = [-1, 0, 1.5, .nan]
        for top in amounts {
            for leading in amounts {
                for bottom in amounts {
                    for trailing in amounts {
                        let insets = EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
                        for rect in rects {
                            #expect(holds(
                                rect.insetBy(insets),
                                rect.x + leading,
                                rect.y + top,
                                Swift.max(0, rect.width - leading - trailing),
                                Swift.max(0, rect.height - top - bottom)
                            ))
                        }
                    }
                }
            }
        }
    }

    @Test func pairwiseOperationsMatchTheScalarFormulas() {
        for a in rects {
            for b in rects {
                let x0 = Swift.max(a.minX, b.minX)
                let y0 = Swift.max(a.minY, b.minY)
                let x1 = Swift.min(a.maxX, b.maxX)
                let y1 = Swift.min(a.maxY, b.maxY)
                let overlap = x1 > x0 && y1 > y0
                #expect(holds(a.intersection(b), x0, y0, overlap ? x1 - x0 : 0, overlap ? y1 - y0 : 0))

                let u0 = Swift.min(a.minX, b.minX)
                let v0 = Swift.min(a.minY, b.minY)
                let u1 = Swift.max(a.maxX, b.maxX)
                let v1 = Swift.max(a.maxY, b.maxY)
                #expect(holds(a.union(b), u0, v0, u1 - u0, v1 - v0))

                #expect(a.intersects(b) == (a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY))
                #expect(a.contains(b) == (b.minX >= a.minX && b.maxX <= a.maxX && b.minY >= a.minY && b.maxY <= a.maxY))
            }
        }
    }
}
