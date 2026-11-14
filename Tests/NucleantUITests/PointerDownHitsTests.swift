//
//  PointerDownHitsTests.swift
//  NucleantUITests
//
//  What a pointer going down looks for, found in one walk, is what a walk
//  for each kind finds: the focus target, the scroll target, the drag and
//  menu sources, and where the press chain starts.
//

import Testing
@testable import NucleantUI

/// Every kind a press looks for, nested and side by side, inside a scroll
/// view.
@View
struct PointerDownScene {
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Color.red.frame(height: 30).onTapGesture {}
                Color.blue.frame(height: 30).draggable("row")
                Color.green.frame(height: 30).contextMenu { Text("Menu") }
                Color.gray.frame(height: 30).focusable()
                Color.orange.frame(height: 30).onLongPressGesture {}
                HStack(spacing: 0) {
                    Color.pink.onTapGesture {}.draggable("a")
                    Color.purple.contextMenu { Text("b") }.focusable()
                }
                .frame(height: 30)
                .onTapGesture {}
            }
            .padding(8)
        }
    }
}

@MainActor
@Suite
struct PointerDownHitsTests {

    private let size = Size(width: 200, height: 240)

    private func placedTree() -> ViewNode {
        var context = BuildContext(
            environment: EnvironmentValues(),
            store: StateStore(),
            effects: EffectQueue(),
            animations: AnimationStore(),
            records: RebuildRecords()
        )
        let node = buildNode(PointerDownScene(), &context)
        var list = DisplayList()
        let window = Rect(origin: .zero, size: size)
        node.place(in: window, proposal: ProposedSize(size), context: DrawContext(), into: &list)
        return node
    }

    private func same<A, B>(_ a: Hit<A>?, _ b: Hit<B>?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?): return a.node === b.node && a.localPoint == b.localPoint && a.frame == b.frame
        default: return false
        }
    }

    @Test func oneWalkFindsWhatAWalkForEachKindFinds() {
        let root = placedTree()
        var found = (focus: 0, scroll: 0, drag: 0, menu: 0, press: 0)
        for y in stride(from: 0.0, through: size.height, by: 3) {
            for x in stride(from: 0.0, through: size.width, by: 7) {
                let point = Point(x: x, y: y)
                let hits = root.pointerDownHits(at: point, scroll: true, contextMenu: true)

                let focus = root.hitTest(point, lookingFor: .focusTarget) { node in
                    node.content.focusTarget.flatMap { $0.isEnabled ? $0 : nil }
                }
                let scroll = root.hitTest(point, matching: { $0.handlesScroll })
                let drag = root.hitTest(point, lookingFor: .dragSource) { $0.content.dragSource }
                let menu = root.hitTest(point, lookingFor: .contextMenuSource) { $0.content.contextMenuSource }
                let chain = root.pressChain(at: point)

                #expect(same(hits.focus, focus), "focus at \(point)")
                #expect(same(hits.scroll, scroll), "scroll at \(point)")
                #expect(same(hits.dragSource, drag), "drag source at \(point)")
                #expect(same(hits.contextMenu, menu), "context menu at \(point)")
                let fromHits = PressChain(from: hits.pressLeaf, at: point)
                #expect(same(fromHits.press, chain.press), "press at \(point)")
                #expect(fromHits.gestures.map(\.hit.node).elementsEqual(chain.gestures.map(\.hit.node), by: ===),
                        "gestures at \(point)")

                if focus != nil { found.focus += 1 }
                if scroll != nil { found.scroll += 1 }
                if drag != nil { found.drag += 1 }
                if menu != nil { found.menu += 1 }
                if chain.press != nil { found.press += 1 }
            }
        }
        // The scene has every kind somewhere under the grid.
        #expect(found.focus > 0 && found.scroll > 0 && found.drag > 0 && found.menu > 0 && found.press > 0)
    }

    @Test func kindsNotAskedForAreNotLookedFor() {
        let root = placedTree()
        let point = Point(x: 100, y: 60)
        let hits = root.pointerDownHits(at: point, scroll: false, contextMenu: false)
        #expect(hits.scroll == nil)
        #expect(hits.contextMenu == nil)
    }
}
