//
//  ScrollClipDisabledTests.swift
//  NucleantUITests
//
//  `.scrollClipDisabled`: what a scroll view's content is cut to with it
//  and without, that what is drawn past the scroll view takes no taps, and
//  that a lazy stack inside still builds only some of its rows.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct ScrollClipDisabledDrawingTests {

    /// The clip the content of a 100×100 scroll view, centered in 200×200
    /// at (50, 50), is drawn under.
    private func contentClip(clipDisabled: Bool?) throws -> Rect? {
        let scroll = ScrollView {
            Color.red.frame(width: 100, height: 300)
        }
        .frame(width: 100, height: 100)
        let list: DisplayList
        if let clipDisabled {
            list = OffscreenRender(environment: EnvironmentValues())
                .list(of: ZStack { scroll.scrollClipDisabled(clipDisabled) }, size: Size(width: 200, height: 200))
        } else {
            list = OffscreenRender(environment: EnvironmentValues())
                .list(of: ZStack { scroll }, size: Size(width: 200, height: 200))
        }
        try #require(!list.isEmpty)
        return list.state(at: 0).clip
    }

    @Test(arguments: [nil, false])
    func aScrollViewCutsItsContentToItsFrame(clipDisabled: Bool?) throws {
        #expect(try contentClip(clipDisabled: clipDisabled) == Rect(x: 50, y: 50, width: 100, height: 100))
    }

    @Test func withItsClipOffTheContentIsCutOneViewportOutFromEachEdge() throws {
        #expect(try contentClip(clipDisabled: true) == Rect(x: -50, y: -50, width: 300, height: 300))
    }
}

// MARK: - Hosted

/// Two 100-wide buttons in a 100-wide strip centered in 200×200 with its
/// clip off: the second one drawn past the strip's trailing edge.
@View
struct PeekingShelf {
    let probe: ScrollProbe

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Button { probe.taps += 1 } label: {
                    Color.red.frame(width: 100, height: 100)
                }
                Button { probe.taps += 10 } label: {
                    Color.blue.frame(width: 100, height: 100)
                }
            }
        }
        .frame(width: 100, height: 100)
        .scrollClipDisabled()
    }
}

/// The rows a lazy stack has built.
@MainActor
final class BuiltRows {
    var rows: Set<Int> = []
}

/// A row that notes it was built.
@View
struct NotedRow {
    let built: BuiltRows
    let row: Int

    var body: some View {
        let _ = built.rows.insert(row)
        Color.blue.frame(height: 20)
    }
}

/// A thousand 20-tall rows in a lazy stack, in a scroll view with its clip
/// off.
@View
struct UnclippedLazyRows {
    let built: BuiltRows

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<1000, id: \.self) { row in
                    NotedRow(built: built, row: row)
                }
            }
        }
        .scrollClipDisabled()
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollClipDisabled {

        @Test func whatIsDrawnPastTheScrollViewTakesNoTaps() async {
            let probe = ScrollProbe()
            let harness = Harness(PeekingShelf(probe: probe))

            await harness.tap(Point(x: 100, y: 100))
            #expect(probe.taps == 1, "the first button, inside the strip")

            await harness.tap(Point(x: 175, y: 100))
            #expect(probe.taps == 1, "the second, drawn past the strip's edge")
        }

        @Test func aLazyStackInsideStillBuildsOnlySomeOfItsRows() async {
            let built = BuiltRows()
            let harness = Harness(UnclippedLazyRows(built: built))
            await harness.frames(3)
            #expect(built.rows.isSuperset(of: Set(0..<20)), "the ten in view, and as many drawn below")
            #expect(built.rows.count < 200)
        }
    }
}
