//
//  ContextMenuTests.swift
//  NucleantUITests
//
//  `.contextMenu(menuItems:)` in both forms: the plain one, and the one
//  whose builder is handed where the click landed.
//

import Testing
@testable import NucleantUI

@View
struct PlainContextMenu {
    let log: Log

    var body: some View {
        Color.gray
            .contextMenu {
                Button("Duplicate") { log("duplicate") }
            }
            .frame(width: 100, height: 100)
    }
}

/// The same, built from the click: the row's action reports the point the
/// builder was given.
@View
struct LocatedContextMenu {
    let log: Log

    var body: some View {
        Color.gray
            .contextMenu { location in
                Button("Add Here") { log("add \(Int(location.x)),\(Int(location.y))") }
            }
            .frame(width: 100, height: 100)
    }
}

/// A builder that leaves a row out depending on where the click was: the
/// closure runs per opening, so the rows differ between two clicks.
@View
struct ConditionalContextMenu {
    let log: Log

    var body: some View {
        Color.gray
            .contextMenu { location in
                if location.x < 50 {
                    Button("Left") { log("left") }
                } else {
                    Button("Right") { log("right") }
                }
            }
            .frame(width: 100, height: 100)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ContextMenuTests {

        /// The first row of a menu opened at `anchor`: the panel's padding
        /// down from it, a little in from its left edge.
        static func firstRow(of anchor: Point) -> Point {
            Point(x: anchor.x + 30, y: anchor.y + ContextMenuPanel.inset + 10)
        }

        @Test func aRightClickOpensTheMenuAndARowRunsItsAction() async {
            let log = Log()
            let harness = Harness(PlainContextMenu(log: log))
            harness.host.secondaryClick(at: Point(x: 70, y: 60))
            await harness.settle()
            await harness.tap(Self.firstRow(of: Point(x: 70, y: 60)))
            #expect(log.take() == ["duplicate"])
        }

        @Test func theBuilderIsHandedTheClickInTheViewsOwnSpace() async {
            let log = Log()
            // The 100×100 colour is centred in the 200×200 host, so its
            // own origin is (50, 50) in window coordinates.
            let harness = Harness(LocatedContextMenu(log: log))
            let click = Point(x: 70, y: 60)
            harness.host.secondaryClick(at: click)
            await harness.settle()
            await harness.tap(Self.firstRow(of: click))
            #expect(log.take() == ["add 20,10"])
        }

        @Test func theBuilderRunsAgainForEachOpening() async {
            let log = Log()
            let harness = Harness(ConditionalContextMenu(log: log))
            // Local x 10: the left branch.
            let left = Point(x: 60, y: 60)
            harness.host.secondaryClick(at: left)
            await harness.settle()
            await harness.tap(Self.firstRow(of: left))
            #expect(log.take() == ["left"])

            // Local x 90: the right one, from the same view.
            let right = Point(x: 140, y: 60)
            harness.host.secondaryClick(at: right)
            await harness.settle()
            await harness.tap(Self.firstRow(of: right))
            #expect(log.take() == ["right"])
        }

        @Test func aClickOutsideAnyMenuedViewOpensNothing() async {
            let log = Log()
            let harness = Harness(LocatedContextMenu(log: log))
            harness.host.secondaryClick(at: Point(x: 5, y: 5))
            await harness.settle()
            await harness.tap(Self.firstRow(of: Point(x: 5, y: 5)))
            #expect(log.take() == [])
        }
    }
}
