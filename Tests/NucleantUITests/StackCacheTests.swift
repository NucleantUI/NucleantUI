//
//  StackCacheTests.swift
//  NucleantUITests
//
//  What a stack keeps between questions — its flattened children, its last
//  run, how far each child stretches — is dropped when what it was worked
//  out from changes, though the stack itself stands: rows of a `ForEach`
//  rebuilt on their own, inside a group the stack dissolves, or a row that
//  grew. The same for the stack views, the stack layouts, and a stack
//  layout behind `AnyLayout`.
//

import Observation
import Testing
@testable import NucleantUI

@MainActor
@Observable
final class RowModel {
    var items: [Int] = [1, 2, 3]
    var isTall = false
}

/// The rows, read by this view alone: a change to them rebuilds it and
/// leaves the stack around it standing.
@View
struct StackedRows {
    let model: RowModel
    let log: Log

    var body: some View {
        let height: Double = model.isTall ? 40 : 20
        ForEach(model.items, id: \.self) { item in
            Color.red.frame(height: height).onTapGesture { log("row \(item)") }
        }
    }
}

/// How the rows and a footer are stacked.
enum RowStacking: CaseIterable {
    case view, layout, anyLayout
}

@View
struct RowsAndFooter {
    let model: RowModel
    let log: Log
    let stacking: RowStacking

    var body: some View {
        switch stacking {
        case .view:
            VStack(spacing: 0) {
                StackedRows(model: model, log: log)
                Color.blue.frame(height: 20).onTapGesture { log("footer") }
            }
            .frame(width: 100, height: 200, alignment: .top)
        case .layout:
            VStackLayout(spacing: 0) {
                StackedRows(model: model, log: log)
                Color.blue.frame(height: 20).onTapGesture { log("footer") }
            }
            .frame(width: 100, height: 200, alignment: .top)
        case .anyLayout:
            AnyLayout(VStackLayout(spacing: 0)) {
                StackedRows(model: model, log: log)
                Color.blue.frame(height: 20).onTapGesture { log("footer") }
            }
            .frame(width: 100, height: 200, alignment: .top)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct StackCacheTests {

        /// What a tap at each height hits, top to bottom.
        private func hits(_ harness: Harness, _ log: Log, at heights: [Double]) async -> [String] {
            for y in heights {
                await harness.tap(Point(x: 100, y: y))
            }
            return log.take()
        }

        @Test(arguments: RowStacking.allCases)
        func rowsChangedBeneathAStandingStackAreLaidOutAgain(stacking: RowStacking) async {
            let model = RowModel()
            let log = Log()
            let harness = Harness(RowsAndFooter(model: model, log: log, stacking: stacking))
            #expect(await hits(harness, log, at: [10, 50, 70]) == ["row 1", "row 3", "footer"])

            await harness.change { model.items = [0, 1, 2, 3] }
            #expect(await hits(harness, log, at: [10, 70, 90]) == ["row 0", "row 3", "footer"], "a row more")

            await harness.change { model.items = [2] }
            #expect(await hits(harness, log, at: [10, 30]) == ["row 2", "footer"], "three rows fewer")

            await harness.change { model.isTall = true }
            #expect(await hits(harness, log, at: [30, 50]) == ["row 2", "footer"], "the row grew")

            await harness.change { model.items = [] }
            #expect(await hits(harness, log, at: [10]) == ["footer"], "no rows")
        }
    }
}
