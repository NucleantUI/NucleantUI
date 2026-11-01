//
//  ButtonTests.swift
//  NucleantUITests
//

import Testing
@testable import NucleantUI

/// A button whose label is a 60×40 block in the top-left corner.
@View
struct BlockButton {
    let log: Log

    var body: some View {
        Button { log("button") } label: {
            Color.red.frame(width: 60, height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ButtonTests {

        @Test func theLabelIsTheWholeButton() async {
            let log = Log()
            let harness = Harness(BlockButton(log: log))
            await harness.tap(Point(x: 30, y: 20))
            #expect(log.take() == ["button"])
            // Just past the label's edges: nothing of the button is there.
            await harness.tap(Point(x: 65, y: 20))
            await harness.tap(Point(x: 30, y: 45))
            #expect(log.take() == [], "a button adds no padding around its label")
        }

        @Test func releasingOutsideCancels() async {
            let log = Log()
            let harness = Harness(BlockButton(log: log))
            harness.host.pointerDown(id: 0, at: Point(x: 30, y: 20))
            harness.host.pointerUp(id: 0, at: Point(x: 150, y: 150))
            await harness.settle()
            #expect(log.take() == [])
        }
    }
}
