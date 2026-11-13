//
//  ToolbarTests.swift
//  NucleantUITests
//
//  `.toolbar { }` on a `NavigationStack`'s screens: where each placement
//  goes in the bars and in what order, how several `.toolbar`s add up,
//  that an item is built in the environment it was written in and follows
//  the screen's state, the "…" for `.secondaryAction`, the bottom bar, a
//  bar with nothing to show, and a back button of the screen's own through
//  `.navigationBarBackButtonHidden()`.
//
//  The stack is 400 × 300: the navigation bar 0…44, 12 points of padding
//  on each side, and a bottom bar 256…300 when there is one.
//

import Testing
@testable import NucleantUI

/// A strip across the top of a screen and one along its bottom, each
/// logging its name when tapped, so a tap says where the screen is.
@View
struct ToolbarScreenStrips {
    let log: Log

    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 20).onTapGesture { log("top strip") }
            Spacer()
            Color.red.frame(height: 20).onTapGesture { log("bottom strip") }
        }
    }
}

/// A root whose toolbar button counts its own taps, from the screen's
/// state: each tap logs what the label said.
@View
struct ToolbarCounter {
    let log: Log
    @State private var count = 0

    var body: some View {
        NavigationStack("Root") {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Color.blue.frame(width: 30, height: 30).onTapGesture {
                            log("count \(count)")
                            count += 1
                        }
                    }
                }
        }
    }
}

/// A root with an extra item while `showsExtra`, listed in the builder or
/// by a `.toolbar` that is in the tree only then. A tap on the top strip
/// turns it off.
@View
struct ToolbarComingAndGoing {
    let log: Log
    let byModifier: Bool
    @State private var showsExtra = true

    var body: some View {
        NavigationStack("Root") {
            VStack(spacing: 0) {
                Color.red.frame(height: 20).onTapGesture { showsExtra = false }
                if byModifier, showsExtra {
                    Color.clear.frame(height: 1).toolbar {
                        ToolbarItem { extra }
                    }
                }
                Spacer()
            }
            .toolbar {
                if !byModifier, showsExtra {
                    ToolbarItem { extra }
                }
            }
        }
    }

    private var extra: some View {
        Color.blue.frame(width: 30, height: 30).onTapGesture { log("extra") }
    }
}

/// One screen pushed on a titled root, its back button replaced by an
/// orange square of its own.
@View
struct ToolbarOwnBackButton {
    let log: Log
    @State private var path = NavigationPath([1])

    var body: some View {
        NavigationStack(path: $path) {
            ToolbarScreenStrips(log: log)
                .navigationTitle("Root")
                .navigationDestination(for: Int.self) { _ in
                    OwnBackButtonScreen(log: log)
                }
        }
    }
}

@View
struct OwnBackButtonScreen {
    let log: Log
    @Environment(\.navigationRouter) private var router

    var body: some View {
        Color.clear
            .navigationTitle("Page")
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Color.orange.frame(width: 30, height: 30).onTapGesture {
                        log("own back")
                        router?.pop()
                    }
                }
            }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ToolbarTests {

        static let size = Size(width: 400, height: 300)

        private func list(_ view: some View) -> DisplayList {
            OffscreenRender(environment: EnvironmentValues()).list(of: view, size: Self.size)
        }

        /// Each text drawn, by its string.
        private func texts(_ view: some View) -> [String: TextDraw] {
            var texts: [String: TextDraw] = [:]
            for case .text(let draw) in list(view).commands {
                texts[draw.string] = draw
            }
            return texts
        }

        private func frames(_ view: some View) -> [String: Rect] {
            texts(view).mapValues(\.frame)
        }

        private func svgs(_ view: some View) -> [SvgDraw] {
            list(view).commands.compactMap {
                if case .svg(let draw) = $0 { return draw }
                return nil
            }
        }

        /// The strings drawn whose frames sit on `y`, left to right.
        private func row(_ frames: [String: Rect], _ names: Set<String>) -> [String] {
            frames.filter { names.contains($0.key) }.sorted { $0.value.minX < $1.value.minX }.map(\.key)
        }

        // MARK: Where each placement goes

        @Test func eachPlacementHasItsSideAndPlace() {
            // Written out of order: the placement decides where each goes.
            let frames = frames(NavigationStack("Root") {
                Color.clear.toolbar {
                    ToolbarItem(placement: .confirmationAction) { Text("C") }
                    ToolbarItem(placement: .primaryAction) { Text("P") }
                    ToolbarItem(placement: .topBarTrailing) { Text("T") }
                    ToolbarItem { Text("A") }
                    ToolbarItem(placement: .destructiveAction) { Text("D") }
                    ToolbarItem(placement: .navigation) { Text("N") }
                    ToolbarItem(placement: .cancellationAction) { Text("X") }
                    ToolbarItem(placement: .topBarLeading) { Text("L") }
                }
            })
            #expect(row(frames, ["L", "X", "N", "Root", "A", "T", "P", "C", "D"])
                == ["L", "X", "N", "Root", "A", "T", "P", "C", "D"])
            #expect(frames["L"]?.minX == 12)
            #expect(frames["D"]?.maxX == 388)
            // All in the navigation bar.
            #expect(frames.values.allSatisfy { $0.minY >= 0 && $0.maxY <= 44 })
        }

        @Test func navigationGoesTrailingWhenTheBackButtonHoldsTheLeadingEdge() {
            let pushed = frames(NavigationStack(path: .constant(NavigationPath([1]))) {
                Color.clear.navigationTitle("Root").navigationDestination(for: Int.self) { _ in
                    Color.clear.navigationTitle("Page").toolbar {
                        ToolbarItem(placement: .primaryAction) { Text("P") }
                        ToolbarItem(placement: .navigation) { Text("N") }
                        ToolbarItem(placement: .topBarTrailing) { Text("T") }
                    }
                }
            })
            #expect(row(pushed, ["Page", "T", "N", "P"]) == ["Page", "T", "N", "P"])
        }

        @Test func withTheBackButtonHiddenNavigationIsLeadingAgain() {
            let view = NavigationStack(path: .constant(NavigationPath([1]))) {
                Color.clear.navigationTitle("Root").navigationDestination(for: Int.self) { _ in
                    Color.clear.navigationTitle("Page")
                        .navigationBarBackButtonHidden()
                        .toolbar {
                            ToolbarItem(placement: .navigation) { Text("N") }
                        }
                }
            }
            let frames = frames(view)
            #expect(row(frames, ["N", "Page"]) == ["N", "Page"])
            #expect(frames["N"]?.minX == 12)
            #expect(svgs(view).filter { $0.image === Icons.shared.back }.isEmpty)
        }

        @Test func principalTakesTheTitlesPlaceInTheMiddle() {
            let frames = frames(NavigationStack("Root") {
                Color.clear.toolbar {
                    ToolbarItem(placement: .principal) { Text("Middle") }
                    ToolbarItem(placement: .principal) { Text("Second") }
                }
            })
            #expect(frames["Root"] == nil)
            #expect(frames["Second"] == nil)
            #expect(abs((frames["Middle"]?.midX ?? 0) - 200) < 0.5)
        }

        @Test func theTitleTakesAllTheRoomTheItemsLeave() {
            // About 217 points: more than half the room "Done" leaves, less
            // than all of it.
            let title = "Write the launch post"
            let frames = frames(NavigationStack(title) {
                Color.clear.toolbar {
                    ToolbarItem(placement: .confirmationAction) { Text("Done") }
                }
            })
            // Whole, not cut at a share of the bar it splits with a spacer.
            let width = TextMeasurer.width(of: title, font: .system(size: 17, weight: .semibold))
            #expect((frames[title]?.width ?? 0) >= width)
            #expect((frames[title]?.maxX ?? .infinity) <= (frames["Done"]?.minX ?? 0))
        }

        @Test func viewsInAToolbarAreAutomaticItems() {
            let frames = frames(NavigationStack("Root") {
                Color.clear.toolbar {
                    Text("One")
                    Text("Two")
                }
            })
            #expect(row(frames, ["Root", "One", "Two"]) == ["Root", "One", "Two"])
            #expect(frames["Two"]?.maxX == 388)
        }

        // MARK: Several toolbars

        @Test func anOuterToolbarsItemsComeBeforeAnInnerOnes() {
            let frames = frames(NavigationStack("Root") {
                Color.clear
                    .toolbar { ToolbarItem { Text("Inner") } }
                    .toolbar { ToolbarItem { Text("Outer") } }
            })
            #expect(row(frames, ["Inner", "Outer"]) == ["Outer", "Inner"])
        }

        @Test func siblingsItemsComeInTheOrderWritten() {
            let frames = frames(NavigationStack("Root") {
                VStack {
                    Color.clear.toolbar { ToolbarItem { Text("First") } }
                    Color.clear.toolbar { ToolbarItem { Text("Second") } }
                }
            })
            #expect(row(frames, ["First", "Second"]) == ["First", "Second"])
        }

        @Test func aToolbarOutsideTheStacksScreensShowsNothing() {
            let frames = frames(NavigationStack("Root") { Color.clear }.toolbar {
                ToolbarItem { Text("Lost") }
            })
            #expect(frames["Lost"] == nil)
            #expect(frames["Root"] != nil)
        }

        // MARK: The item's own environment and state

        @Test func anItemIsBuiltInTheEnvironmentItWasWrittenIn() {
            let texts = texts(NavigationStack("Root") {
                Color.clear
                    .toolbar { ToolbarItem { Text("Red") } }
                    .foregroundColor(.red)
            })
            #expect(texts["Red"]?.color == .red)
            // The bar's own title is not.
            #expect(texts["Root"]?.color != .red)
        }

        @Test func anItemFollowsTheScreensState() async {
            let log = Log()
            let harness = Harness(ToolbarCounter(log: log), size: Self.size)
            let button = Point(x: 373, y: 22)
            await harness.tap(button)
            await harness.settle()
            await harness.tap(button)
            await harness.settle()
            await harness.tap(button)
            #expect(log.take() == ["count 0", "count 1", "count 2"])
        }

        @Test(arguments: [false, true])
        func anItemThatGoesGoesFromTheBar(byModifier: Bool) async {
            let log = Log()
            let harness = Harness(ToolbarComingAndGoing(log: log, byModifier: byModifier), size: Self.size)
            let extra = Point(x: 373, y: 22)
            await harness.tap(extra)
            #expect(log.take() == ["extra"])
            await harness.tap(Point(x: 100, y: 54))
            await harness.settle()
            await harness.settle()
            await harness.tap(extra)
            #expect(log.take() == [])
        }

        // MARK: Secondary actions

        @Test func secondaryActionsAreBehindTheEllipsis() {
            let view = NavigationStack("Root") {
                Color.clear.toolbar {
                    ToolbarItem(placement: .secondaryAction) { Text("Archive") }
                    ToolbarItem(placement: .primaryAction) { Text("Add") }
                }
            }
            let frames = frames(view)
            #expect(frames["Archive"] == nil)
            let more = svgs(view).filter { $0.image === Icons.shared.more }
            #expect(more.count == 1)
            // At the trailing edge, after the primary action.
            #expect((more.first?.frame.minX ?? 0) > (frames["Add"]?.maxX ?? .infinity))
            #expect(abs((more.first?.frame.midX ?? 0) - 370) < 0.5)
        }

        @Test func theEllipsisOpensTheMenu() async {
            let log = Log()
            let presenter = MenuPresenter { _ in log("menu") }
            let view = NavigationStack("Root") {
                Color.clear.toolbar {
                    ToolbarItem(placement: .secondaryAction) { Text("Archive") }
                }
            }
            .environment(\.menuPresenter, presenter)
            let harness = Harness(view, size: Self.size)
            await harness.tap(Point(x: 370, y: 22))
            #expect(log.take() == ["menu"])
        }

        // MARK: The bottom bar

        @Test func bottomItemsGoInABarAlongTheBottom() async {
            let log = Log()
            let view = NavigationStack("Root") {
                ToolbarScreenStrips(log: log).toolbar {
                    ToolbarItem(placement: .bottomBar) { Text("Left") }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { Text("Right") }
                }
            }
            let frames = frames(view)
            #expect(frames["Left"]?.minX == 12)
            #expect(frames["Right"]?.maxX == 388)
            #expect((frames["Left"]?.minY ?? 0) > 256)
            // The screen ends where the bar begins.
            let harness = Harness(view, size: Self.size)
            await harness.tap(Point(x: 100, y: 246))
            #expect(log.take() == ["bottom strip"])
        }

        @Test func aStatusItemIsCentredBetweenFlexibleSpaces() {
            // An item as wide on each side: centred between them is centred
            // in the bar.
            let frames = frames(NavigationStack("Root") {
                Color.clear.toolbar {
                    ToolbarItem(placement: .bottomBar) { Color.blue.frame(width: 30, height: 30) }
                    ToolbarItem(placement: .status) { Text("Saved") }
                    ToolbarItem(placement: .bottomBar) { Color.blue.frame(width: 30, height: 30) }
                }
            })
            #expect(abs((frames["Saved"]?.midX ?? 0) - 200) < 0.5)
        }

        @Test func aLoneBottomItemIsCentred() {
            let frames = frames(NavigationStack("Root") {
                Color.clear.toolbar {
                    ToolbarItem(placement: .bottomBar) { Text("Only") }
                }
            })
            #expect(abs((frames["Only"]?.midX ?? 0) - 200) < 0.5)
        }

        @Test func aScreenHidesTheBottomBar() async {
            let log = Log()
            let view = NavigationStack("Root") {
                ToolbarScreenStrips(log: log)
                    .toolbar { ToolbarItem(placement: .bottomBar) { Text("Hidden") } }
                    .toolbarVisibility(.hidden, for: .bottomBar)
            }
            #expect(frames(view)["Hidden"] == nil)
            let harness = Harness(view, size: Self.size)
            await harness.tap(Point(x: 100, y: 290))
            #expect(log.take() == ["bottom strip"])
        }

        // MARK: A bar with nothing to show

        @Test func aRootWithNothingForTheBarHasNone() async {
            let log = Log()
            let harness = Harness(NavigationStack { ToolbarScreenStrips(log: log) }, size: Self.size)
            await harness.tap(Point(x: 100, y: 10))
            #expect(log.take() == ["top strip"])
        }

        @Test func aRootWithOnlyItemsHasABar() {
            let frames = frames(NavigationStack {
                Color.clear.toolbar { ToolbarItem { Text("Item") } }
            })
            #expect((frames["Item"]?.minY ?? 99) < 44)
        }

        @Test func visibleKeepsAnEmptyBar() async {
            let log = Log()
            let harness = Harness(NavigationStack {
                ToolbarScreenStrips(log: log).toolbarVisibility(.visible, for: .navigationBar)
            }, size: Self.size)
            await harness.tap(Point(x: 100, y: 54))
            #expect(log.take() == ["top strip"])
        }

        @Test func aPushedScreenWithoutATitleKeepsItsBarForTheBackButton() {
            let view = NavigationStack(path: .constant(NavigationPath([1]))) {
                Color.clear.navigationDestination(for: Int.self) { _ in Color.clear }
            }
            #expect(svgs(view).filter { $0.image === Icons.shared.back }.count == 1)
        }

        // MARK: A back button of the screen's own

        @Test func aScreensOwnBackButtonTakesTheLeadingEdge() async {
            let log = Log()
            let view = ToolbarOwnBackButton(log: log)
            #expect(svgs(view).filter { $0.image === Icons.shared.back }.isEmpty)
            let harness = Harness(view, size: Self.size)
            // The orange square, at 12…42.
            await harness.tap(Point(x: 27, y: 22))
            await harness.settle(1.0 / 60)
            await harness.settle(0.6)
            await harness.settle(0.02)
            await harness.tap(Point(x: 100, y: 54))
            #expect(log.take() == ["own back", "top strip"])
        }
    }
}
