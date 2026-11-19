//
//  SystemBarsTests.swift
//  NucleantUITests
//
//  `.statusBarHidden(_:)`, `.toolbarVisibility(_:for: .statusBar)` and
//  `.persistentSystemOverlays(_:)`: what reaches the host's root is what
//  the window is told. The deepest view to ask decides, a covered
//  `NavigationStack` screen has no say, and the window hears of a change
//  once, and only of a change.
//

import Testing
@testable import NucleantUI

/// The three spellings that hide the status bar.
enum StatusBarHidingSpelling: CaseIterable {
    case statusBarHidden
    case toolbarVisibility
    case toolbar
}

@View
struct SystemBarsNothingAsked {
    var body: some View {
        Color.red
    }
}

@View
struct StatusBarHiddenBy {
    let spelling: StatusBarHidingSpelling

    var body: some View {
        switch spelling {
        case .statusBarHidden:
            Color.red.statusBarHidden()
        case .toolbarVisibility:
            Color.red.toolbarVisibility(.hidden, for: .statusBar)
        case .toolbar:
            Color.red.toolbar(.hidden, for: .statusBar)
        }
    }
}

@View
struct SystemOverlaysHidden {
    var body: some View {
        Color.red.persistentSystemOverlays(.hidden)
    }
}

/// The app around asks for the bar, a view inside it asks it away; for the
/// overlays, the other way round.
@View
struct SystemBarsInnerDecides {
    var body: some View {
        VStack {
            Color.red
                .statusBarHidden()
                .persistentSystemOverlays(.visible)
        }
        .statusBarHidden(false)
        .persistentSystemOverlays(.hidden)
    }
}

/// Two views side by side that disagree.
@View
struct SystemBarsSiblings {
    var body: some View {
        HStack {
            Color.red.statusBarHidden(false)
            Color.green.statusBarHidden(true)
        }
    }
}

/// A tap hides both; a second tap shows them. The lower half counts taps,
/// which the bars don't care about.
@View
struct SystemBarsToggled {
    @State private var hidden = false
    @State private var count = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 100).onTapGesture { hidden.toggle() }
            Text("\(count)").frame(height: 100).onTapGesture { count += 1 }
        }
        .statusBarHidden(hidden)
        .persistentSystemOverlays(hidden ? .hidden : .automatic)
    }
}

/// `.statusBar` alone leaves the stack's own bar where it is.
@View
struct StatusBarOnlyInStack {
    let log: Log

    var body: some View {
        NavigationStack("Root") {
            BarTestStrip(log: log, name: "root")
                .toolbarVisibility(.hidden, for: .statusBar)
        }
    }
}

/// The root hides the status bar and the overlays; the screen pushed over
/// it asks nothing.
@View
struct SystemBarsPerScreen {
    let log: Log

    var body: some View {
        NavigationStack("Root") {
            VStack(spacing: 0) {
                NavigationLink(title: "Next") {
                    BarTestStrip(log: log, name: "next")
                } label: {
                    Color.green.frame(height: 20)
                }
                Spacer()
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct SystemBarsTests {

        @Test func nothingAskedIsAutomatic() {
            let harness = Harness(SystemBarsNothingAsked())
            #expect(harness.host.statusBarVisibility == .automatic)
            #expect(harness.host.persistentSystemOverlays == .automatic)
        }

        @Test(arguments: StatusBarHidingSpelling.allCases)
        func eachSpellingHidesTheStatusBar(spelling: StatusBarHidingSpelling) {
            let harness = Harness(StatusBarHiddenBy(spelling: spelling))
            #expect(harness.host.statusBarVisibility == .hidden)
            #expect(harness.host.persistentSystemOverlays == .automatic)
        }

        @Test func theOverlaysAreTheirOwn() {
            let harness = Harness(SystemOverlaysHidden())
            #expect(harness.host.persistentSystemOverlays == .hidden)
            #expect(harness.host.statusBarVisibility == .automatic)
        }

        @Test func theDeepestViewDecides() {
            let harness = Harness(SystemBarsInnerDecides())
            #expect(harness.host.statusBarVisibility == .hidden)
            #expect(harness.host.persistentSystemOverlays == .visible)
        }

        @Test func theLastOfTwoSiblingsDecides() {
            let harness = Harness(SystemBarsSiblings())
            #expect(harness.host.statusBarVisibility == .hidden)
        }

        @Test func theWindowIsToldOfEachChangeOnce() async {
            let log = Log()
            let harness = Harness(SystemBarsToggled())
            harness.host.onSystemBarsChange = { [unowned host = harness.host] in
                log("\(host.statusBarVisibility) \(host.persistentSystemOverlays)")
            }

            await harness.tap(Point(x: 100, y: 50))
            #expect(log.take() == ["hidden hidden"])

            // A state change the bars don't read: nothing to tell.
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == [])

            await harness.tap(Point(x: 100, y: 50))
            #expect(log.take() == ["visible automatic"])
        }

        @Test func theStatusBarLeavesTheStacksBarAlone() async {
            let log = Log()
            let harness = Harness(StatusBarOnlyInStack(log: log))
            #expect(harness.host.statusBarVisibility == .hidden)
            // The strip is still under the stack's 44-point bar.
            await harness.tap(Point(x: 100, y: 10))
            #expect(log.take() == [])
            await harness.tap(Point(x: 100, y: 54))
            #expect(log.take() == ["root"])
        }

        /// A push or pop played out, as in `NavigationBarVisibilityTests`.
        private func playMove(_ harness: Harness) async {
            await harness.settle(1.0 / 60)
            await harness.settle(0.6)
            await harness.settle(0.02)
        }

        @Test func aCoveredScreenHasNoSay() async {
            let log = Log()
            let harness = Harness(SystemBarsPerScreen(log: log))
            #expect(harness.host.statusBarVisibility == .hidden)
            #expect(harness.host.persistentSystemOverlays == .hidden)

            // Push: the screen on top asks nothing, so the system decides.
            await harness.tap(Point(x: 100, y: 54))
            await playMove(harness)
            await harness.tap(Point(x: 100, y: 54))
            #expect(log.take() == ["next"])
            #expect(harness.host.statusBarVisibility == .automatic)
            #expect(harness.host.persistentSystemOverlays == .automatic)

            // Back: the root is on top again, and what it asked is back.
            await harness.tap(Point(x: 30, y: 22))
            await playMove(harness)
            #expect(harness.host.statusBarVisibility == .hidden)
            #expect(harness.host.persistentSystemOverlays == .hidden)
        }
    }
}
