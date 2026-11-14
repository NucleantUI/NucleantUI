//
//  DisplayListStateTests.swift
//  NucleantUITests
//
//  A display list keeps the clip and transform of its commands as states,
//  one for each run of commands drawn under the same one, and each
//  command's paint bounds from when it was appended.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct DisplayListStateTests {

    private func square(at x: Double) -> DrawCommand {
        .shape(ShapeDraw(
            path: Path { $0.addRect(Rect(x: x, y: 0, width: 10, height: 10)) },
            bounds: Rect(x: x, y: 0, width: 10, height: 10),
            fill: .color(.red)
        ))
    }

    private let clipped = DrawState(clip: Rect(x: 0, y: 0, width: 50, height: 50))
    private let moved = DrawState(transform: .translation(x: 5, y: 0))

    @Test func aRunOfCommandsSharesOneState() {
        var list = DisplayList()
        list.append(square(at: 0), under: clipped)
        list.append(square(at: 20), under: clipped)
        list.append(square(at: 40), under: moved)
        list.append(square(at: 60), under: clipped)
        #expect(list.states == [clipped, moved, clipped], "a new state where one differs from the one before it")
        #expect((0..<4).map(list.stateIndex(at:)) == [0, 0, 1, 2])
        #expect(list.state(at: 3) == clipped)
    }

    @Test func listsJoinedAreTheListBuiltInOne() {
        var whole = DisplayList()
        whole.append(square(at: 0), under: clipped)
        whole.append(square(at: 20), under: clipped)
        whole.append(square(at: 40), under: moved)

        var first = DisplayList()
        first.append(square(at: 0), under: clipped)
        var second = DisplayList()
        second.append(square(at: 20), under: clipped)
        second.append(square(at: 40), under: moved)
        first.append(contentsOf: second)

        #expect(first == whole)
        #expect(first.states.count == 2, "the second list's first run went on with the first's")
        #expect(first.paintBounds(at: 2) == whole.paintBounds(at: 2))
    }

    @Test func aCommandMovedToAnotherListKeepsItsStateAndBounds() {
        var source = DisplayList()
        source.append(square(at: 0), under: moved)
        source.append(square(at: 80), under: clipped)
        var target = DisplayList()
        target.append(1, of: source)
        #expect(target.state(at: 0) == clipped)
        #expect(target.paintBounds(at: 0) == source.paintBounds(at: 1))
    }

    @Test func theSameDrawingIsEqualAndADifferentStateIsNot() {
        var a = DisplayList()
        a.append(square(at: 0), under: clipped)
        var b = DisplayList()
        b.append(square(at: 0), under: clipped)
        var c = DisplayList()
        c.append(square(at: 0), under: moved)
        #expect(a == b)
        #expect(a != c, "the same command under another state draws something else")
        #expect(a.draws(0, as: 0, in: b))
        #expect(!a.draws(0, as: 0, in: c))
    }

    @Test func paintBoundsAreTheBoxUnderTheStateInsideTheClip() {
        var list = DisplayList()
        list.append(square(at: 45), under: clipped)
        list.append(square(at: 0), under: moved)
        list.append(square(at: 100), under: clipped)
        // Grown a pixel for anti-aliasing, then cut to the clip.
        #expect(list.paintBounds(at: 0) == Rect(x: 44, y: 0, width: 6, height: 11))
        // Moved by the transform.
        #expect(list.paintBounds(at: 1) == Rect(x: 4, y: -1, width: 12, height: 12))
        // Clipped away entirely.
        #expect(list.paintBounds(at: 2) == nil)
        #expect(list.paintBounds == Rect(x: 4, y: -1, width: 46, height: 12))
    }

    @Test func aTranslatedListMovesEachStateAndItsBounds() {
        var list = DisplayList()
        list.append(square(at: 0), under: clipped)
        list.append(square(at: 20), under: clipped)
        let shifted = list.translated(dx: 3, dy: 4)
        #expect(shifted.states == [DrawState(clip: Rect(x: 3, y: 4, width: 50, height: 50))])
        #expect(shifted.paintBounds(at: 1) == list.paintBounds(at: 1).map { $0.offsetBy(dx: 3, dy: 4) })

        // What it would be, built where it now is.
        var built = DisplayList()
        built.append(square(at: 0).translated(dx: 3, dy: 4), under: clipped.translated(dx: 3, dy: 4))
        built.append(square(at: 20).translated(dx: 3, dy: 4), under: clipped.translated(dx: 3, dy: 4))
        #expect(shifted == built)
        #expect(shifted.paintBounds(at: 0) == built.paintBounds(at: 0))
    }

    @Test func aKeptListIsKnownByItsNumberAsItIsAndMovedOnce() {
        var kept = DisplayList()
        kept.append(square(at: 0), under: clipped)
        kept.markKept(7)

        var holder = DisplayList()
        holder.append(contentsOf: kept)
        #expect(holder.version == kept.version, "appended into an empty list: that list")

        let image = holder.translated(dx: -3, dy: -4)
        #expect(image.version == DisplayList.Version(kept: 7, dx: -3, dy: -4))
        #expect(image == kept.translated(dx: -3, dy: -4))
        #expect(image.translated(dx: 1, dy: 1).version == nil, "moved twice: compared by its commands")
        #expect(kept.transformed(by: .scale(x: 2, y: 2)).version == nil)

        var grown = holder
        grown.append(square(at: 20), under: clipped)
        #expect(grown.version == nil, "anything added: compared by its commands")
        var joined = holder
        joined.append(contentsOf: kept)
        #expect(joined.version == nil)
    }

    @Test func listsWithoutTheSameNumberAreComparedByTheirCommands() {
        var a = DisplayList()
        a.append(square(at: 0), under: clipped)
        var b = a
        a.markKept(1)
        b.markKept(2)
        #expect(a == b, "kept twice, drawing the same")
        var c = DisplayList()
        c.append(square(at: 20), under: clipped)
        c.markKept(3)
        #expect(a != c)
    }

    @Test func aStateCutToARectReplacesARoundedClipThatHoldsIt() {
        let rounded = DrawState(clip: Rect(x: 0, y: 0, width: 100, height: 100), clipCornerRadius: 10)
        let inside = Rect(x: 20, y: 20, width: 10, height: 10)
        #expect(rounded.clipped(to: inside) == DrawState(clip: inside))
        #expect(!rounded.roundedClipCrosses(inside))
        let corner = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(rounded.clipped(to: corner) == DrawState(clip: corner, clipCornerRadius: 10))
        #expect(rounded.roundedClipCrosses(corner))
    }
}
