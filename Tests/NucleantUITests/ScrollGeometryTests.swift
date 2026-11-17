//
//  ScrollGeometryTests.swift
//  NucleantUITests
//
//  `ScrollGeometry`'s rects.
//

import Foundation
import Testing
@testable import NucleantUI

struct ScrollGeometryTests {

    private let geometry = ScrollGeometry(
        contentOffset: Point(x: 0, y: 300),
        contentSize: Size(width: 200, height: 1000),
        contentInsets: EdgeInsets(top: 20, leading: 10, bottom: 30, trailing: 10),
        containerSize: Size(width: 200, height: 200)
    )

    @Test func theVisibleRectIsTheWholeScrollViewInTheContentsSpace() {
        #expect(geometry.visibleRect == Rect(x: 0, y: 300, width: 200, height: 200))
    }

    @Test func theBoundsAreTheVisibleRectInsideTheInsets() {
        #expect(geometry.bounds == Rect(x: 10, y: 320, width: 180, height: 150))
    }

    @Test func insetsWiderThanTheContainerLeaveBoundsOfNoSize() {
        let squeezed = ScrollGeometry(
            contentOffset: .zero,
            contentSize: Size(width: 100, height: 100),
            contentInsets: EdgeInsets(150),
            containerSize: Size(width: 200, height: 200)
        )
        #expect(squeezed.bounds.size == .zero)
    }

    @Test func geometriesAreEqualWhenEveryPartIs() {
        var moved = geometry
        #expect(moved == geometry)
        moved.contentOffset.y += 1
        #expect(moved != geometry)
    }
}
