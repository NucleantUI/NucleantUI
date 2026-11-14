//
//  PlacementCacheTests.swift
//  NucleantUITests
//
//  A subtree of nodes that place purely, placed again as it was placed the
//  pass before, with nothing in it moving, appends what it drew instead of
//  being placed; whatever changes in it, or moves, is placed again.
//

import Testing
@testable import NucleantUI

/// A leaf that places purely, drawing a square where it is placed. A
/// `moving` one asks for a frame each time, as an animated value on its way
/// does.
private struct Swatch: NodeContent {
    static var placesPurely: Bool { true }
    var moving = false

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        Size(width: 10, height: 10)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        if moving { PlacementRecorder.shared.noteDisturbance() }
        list.append(.shape(ShapeDraw(path: Path(rect), bounds: rect, fill: .color(.red))), under: context.drawState)
    }
}

/// How often an `ImpureLeaf` was placed.
private final class Count {
    var value = 0
}

/// A leaf of a kind that does not say it places purely: placed every pass.
private struct ImpureLeaf: NodeContent {
    let count: Count

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        Size(width: 10, height: 10)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        count.value += 1
    }
}

@MainActor
@Suite
struct PlacementCacheTests {

    private let window = Rect(x: 0, y: 0, width: 100, height: 100)

    private func leaf(moving: Bool = false) -> ViewNode {
        ContentNode(content: Swatch(moving: moving))
    }

    private func stack(_ children: ViewNode...) -> ViewNode {
        ContentNode(content: ZStackContent(alignment: .center), children: children)
    }

    private func place(_ node: ViewNode, in rect: Rect? = nil, context: DrawContext = DrawContext()) -> DisplayList {
        let rect = rect ?? window
        var list = DisplayList()
        node.place(in: rect, proposal: ProposedSize(rect.size), context: context, into: &list)
        return list
    }

    @Test func aSubtreeStandingStillIsKeptAndAppendedAgain() {
        let a = leaf(), b = leaf()
        let root = stack(a, b)
        let first = place(root)
        #expect(root.placed?.list == nil, "placed once: not known yet to stand still")
        let second = place(root)
        #expect(second == first)
        #expect(root.placed?.list == second, "placed the same way twice: kept")

        a.frame = .zero
        let third = place(root)
        #expect(third == first)
        #expect(a.frame == .zero, "not placed: what it drew was appended")
    }

    @Test func aListHoldingOneKeptSubtreeIsTheKeptList() {
        let root = stack(leaf(), leaf())
        _ = place(root)
        _ = place(root)
        let third = place(root)
        #expect(third.version != nil)
        #expect(third.version == root.placed?.list?.version, "appended into an empty list: the kept list")
        #expect(place(root).translated(dx: -5, dy: 0).version == third.translated(dx: -5, dy: 0).version,
                "the same image, told by its number")
    }

    @Test func placedSomewhereElseItIsPlacedAgain() {
        let a = leaf()
        let root = stack(a)
        _ = place(root)
        _ = place(root)
        let moved = Rect(x: 20, y: 0, width: 100, height: 100)
        let there = place(root, in: moved)
        #expect(a.frame == Rect(x: 65, y: 45, width: 10, height: 10))
        #expect(there != place(root), "drawn where it was placed")

        var faded = DrawContext()
        faded.opacity = 0.5
        a.frame = .zero
        _ = place(root, context: faded)
        #expect(a.frame != .zero, "under another context: placed again")
    }

    @Test func aChangeBelowDropsWhatIsKeptAbove() {
        let a = leaf()
        let middle = stack(a)
        let root = stack(middle, leaf())
        _ = place(root)
        _ = place(root)
        #expect(root.placed?.list != nil)

        let replacement = leaf()
        middle.replaceChild(at: 0, with: replacement)
        #expect(root.placed == nil)
        #expect(middle.placed == nil)
        _ = place(root)
        #expect(replacement.frame == Rect(x: 45, y: 45, width: 10, height: 10), "the new child was placed")
    }

    @Test func whatMovesIsPlacedEveryPassAndWhatStandsStillBesideItIsKept() {
        let moving = leaf(moving: true), still = leaf()
        let root = stack(moving, still)
        let first = place(root)
        _ = place(root)
        #expect(root.placed?.list == nil, "something in it moves: not kept as a whole")
        #expect(moving.placed?.list == nil)
        #expect(still.placed?.list != nil, "kept on its own, beside what moves")

        moving.frame = .zero
        still.frame = .zero
        let third = place(root)
        #expect(third == first)
        #expect(moving.frame != .zero, "placed again")
        #expect(still.frame == .zero, "appended")
    }

    @Test func aKindThatDoesNotPlacePurelyIsPlacedEveryPass() {
        let count = Count()
        let still = leaf()
        let root = stack(ContentNode(content: ImpureLeaf(count: count)), still)
        for _ in 0..<3 { _ = place(root) }
        #expect(count.value == 3)
        #expect(root.placed == nil, "a subtree with it is never kept")
        #expect(still.placed?.list != nil, "its pure neighbour keeps itself")
    }

    @Test func aPlacementThatFreezesMotionKeepsNothing() {
        let a = leaf()
        let root = stack(a)
        var snapshot = DrawContext()
        snapshot.freezesMotion = true
        for _ in 0..<3 {
            a.frame = .zero
            _ = place(root, context: snapshot)
            #expect(a.frame != .zero)
        }
        #expect(root.placed == nil)
    }

    @Test func droppingEverythingPlacesAgain() {
        let a = leaf()
        let root = stack(a)
        _ = place(root)
        _ = place(root)
        PlacementRecorder.shared.invalidateAll()
        a.frame = .zero
        _ = place(root)
        #expect(a.frame != .zero)
    }

    @Test func whatIsAppendedJoinsTheListAsPlacingWould() {
        let root = stack(leaf(), leaf())
        func placeAfterACommand() -> DisplayList {
            var list = DisplayList()
            list.append(.shape(ShapeDraw(path: Path(window), bounds: window, fill: .color(.blue))))
            root.place(in: window, proposal: ProposedSize(window.size), context: DrawContext(), into: &list)
            return list
        }
        let first = placeAfterACommand()
        _ = placeAfterACommand()
        let kept = placeAfterACommand()
        #expect(kept == first)
        #expect(kept.states.count == 1, "one state for the command before and the ones appended")
    }
}
