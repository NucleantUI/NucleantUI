//
//  ScrollVisibilityChangeTests.swift
//  NucleantUITests
//
//  `.onScrollVisibilityChange`: a row in a hosted scroll view told when it
//  comes into view and goes out of it.
//

import Foundation
import Testing
@testable import NucleantUI

/// Twenty rows 50 tall in 200; row `watched` reports whether it is in view.
@View
struct WatchedRow {
    let log: Log
    let watched: Int
    let threshold: Double

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { row in
                    if row == watched {
                        Color.red.frame(height: 50)
                            .onScrollVisibilityChange(threshold: threshold) { isVisible in
                                log("row \(row) \(isVisible)")
                            }
                    } else {
                        Color.blue.frame(height: 50)
                    }
                }
            }
        }
    }
}

/// A view in no scroll view.
@View
struct UnscrolledWatched {
    let log: Log

    var body: some View {
        Color.red
            .onScrollVisibilityChange { isVisible in log("\(isVisible)") }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollVisibilityChanges {

        private func scroll(_ harness: Harness, by dy: Double) async {
            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -dy)
            await harness.frames(2)
        }

        @Test func inViewAtFirstItIsToldSoThenToldWhenItGoesAndComesBack() async {
            let log = Log()
            let harness = Harness(WatchedRow(log: log, watched: 1, threshold: 0.5))
            #expect(log.take() == ["row 1 true"])

            await scroll(harness, by: 150)
            #expect(log.take() == ["row 1 false"])

            await scroll(harness, by: -150)
            #expect(log.take() == ["row 1 true"])
        }

        @Test func outOfViewAtFirstItIsToldNothingUntilItComesIntoView() async {
            let log = Log()
            let harness = Harness(WatchedRow(log: log, watched: 10, threshold: 0.5))
            #expect(log.take().isEmpty)

            await scroll(harness, by: 400)
            #expect(log.take() == ["row 10 true"])
        }

        @Test(arguments: [(0.5, ["row 4 true"]), (0.6, [String]())])
        func halfInViewMeetsAThresholdOfHalfAndNoMore(threshold: Double, told: [String]) async {
            let log = Log()
            let harness = Harness(WatchedRow(log: log, watched: 4, threshold: threshold))
            #expect(log.take().isEmpty, "row 4 starts just below the viewport")

            // 25 down: 25 of row 4's 50 points are in view.
            await scroll(harness, by: 25)
            #expect(log.take() == told)
        }

        @Test func inNoScrollViewAViewIsInView() {
            let log = Log()
            _ = Harness(UnscrolledWatched(log: log))
            #expect(log.take() == ["true"])
        }
    }
}
