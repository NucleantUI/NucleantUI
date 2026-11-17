//
//  ContentMarginsTests.swift
//  NucleantUITests
//
//  `.contentMargins`: what it writes for the scroll view below, then a
//  hosted scroll view inset by it.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct ContentMarginsModifierTests {

    /// The margins the scroll view below `modifiers` sees — the first is
    /// the outermost.
    private func margins(under modifiers: [ContentMarginsModifier]) -> ContentMargins {
        var environment = EnvironmentValues()
        for modifier in modifiers { modifier.modifyEnvironment(&environment) }
        return environment.contentMargins
    }

    @Test func automaticInsetsTheContentAndTheIndicators() {
        let set = margins(under: [ContentMarginsModifier(edges: .all, insets: EdgeInsets(12), placement: .automatic)])
        #expect(set.scrollContent == EdgeInsets(12))
        #expect(set.scrollIndicators == EdgeInsets(12))
    }

    @Test(arguments: [ContentMarginPlacement.scrollContent, .scrollIndicators])
    func aPlacementSetsItsOwnMarginsOnly(placement: ContentMarginPlacement) {
        let set = margins(under: [ContentMarginsModifier(edges: .all, insets: EdgeInsets(12), placement: placement)])
        #expect(set.scrollContent == (placement == .scrollContent ? EdgeInsets(12) : EdgeInsets()))
        #expect(set.scrollIndicators == (placement == .scrollIndicators ? EdgeInsets(12) : EdgeInsets()))
    }

    @Test func onlyTheEdgesNamedAreSetAndTheRestKeptFromAbove() {
        let set = margins(under: [
            ContentMarginsModifier(edges: .all, insets: EdgeInsets(10), placement: .scrollContent),
            ContentMarginsModifier(edges: .horizontal, insets: EdgeInsets(20), placement: .scrollContent),
        ])
        #expect(set.scrollContent == EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
    }

    @Test func nothingSetIsNoMargin() {
        #expect(EnvironmentValues().contentMargins == ContentMargins())
    }
}

// MARK: - Hosted

/// Rows 1000 tall in a 200×200 scroll view with margins.
@View
struct MarginedRows {
    let probe: ScrollProbe
    let edges: Edge.Set
    let length: Double

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 1000)
                .onGeometryChange(for: Rect.self) { $0.frame(in: .scrollView) } action: { frame in
                    probe.top = frame.minY
                    probe.leading = frame.minX
                    probe.width = frame.width
                }
        }
        .contentMargins(edges, length)
    }
}

/// A sideways strip inside a scroll view with margins on every edge.
@View
struct MarginedOuterScroll {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            ScrollView(.horizontal) {
                Color.green.frame(width: 1000, height: 100)
                    .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView(axis: .horizontal)).minX } action: { probe.leading = $0 }
            }
        }
        .contentMargins(30)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ContentMarginsOnScrollViews {

        @Test func theContentStartsInsideTheMarginAndScrollsToItsEndPastIt() async {
            let probe = ScrollProbe()
            let harness = Harness(MarginedRows(probe: probe, edges: .vertical, length: 20))
            #expect(probe.top == 20)

            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -5000)
            await harness.frames(2)
            #expect(probe.top == -820, "its end rests the bottom margin above the scroll view's bottom")
        }

        @Test func acrossItIsLaidOutInsideTheMargins() {
            let probe = ScrollProbe()
            _ = Harness(MarginedRows(probe: probe, edges: .horizontal, length: 30))
            #expect(probe.leading == 30)
            #expect(probe.width == 140, "200 wide less 30 each side")
        }

        @Test func aNilLengthIsTheDefaultSixteen() {
            let probe = ScrollProbe()
            _ = Harness(MarginedOuterRowsDefault(probe: probe))
            #expect(probe.top == 16)
        }

        @Test func aScrollViewInsideDoesNotInheritThem() {
            let probe = ScrollProbe()
            _ = Harness(MarginedOuterScroll(probe: probe))
            #expect(probe.leading == 0)
        }
    }
}

@View
struct MarginedOuterRowsDefault {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 1000)
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .contentMargins(.top, nil)
    }
}
