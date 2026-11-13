//
//  NodeTraitsTests.swift
//  NucleantUITests
//
//  What a node can do — be hit, be hovered, clip, be parked — is read off
//  its content when it is made, and what any node below it can do is kept
//  with it, so a walk looking for one kind of node passes over subtrees
//  without any. That union follows the tree as subtrees are replaced.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct NodeTraitsTests {

    private func tapNode() -> ViewNode {
        ContentNode(content: InteractionContent(target: HitTarget(onTap: { _ in })))
    }

    private func hoverNode() -> ViewNode {
        ContentNode(content: HoverContent(target: HoverTarget(path: [], isEnabled: true, action: { _ in })))
    }

    @Test func aNodeHasWhatItsContentCanDo() {
        #expect(tapNode().traits == [.hitTarget])
        #expect(hoverNode().traits == [.hoverTarget])
        #expect(ContentNode(content: GroupContent()).traits == [.transparent])
        #expect(ContentNode(content: ClipContent(cornerRadius: 4)).traits == [.clipsChildren])
        // A parked screen places by its own rules: not a kind that places purely.
        #expect(ContentNode(content: ParkedContent(isParked: true)).traits == [.parked, .placesImpurely])
        #expect(ContentNode(content: ParkedContent(isParked: false)).traits == [.placesImpurely])
        #expect(ContentNode(content: HitTestingContent(allowsHitTesting: false)).traits == [.blocksHitTesting])
        #expect(ContentNode(content: PaddingContent(insets: .zero)).traits == [])
    }

    @Test func aSubtreeHasWhatAnyNodeInItCan() {
        let middle = ContentNode(content: PaddingContent(insets: .zero), children: [tapNode()])
        let root = ContentNode(content: GroupContent(), children: [middle, hoverNode()])
        #expect(root.traits == [.transparent])
        #expect(root.subtreeTraits == [.transparent, .hitTarget, .hoverTarget])
        #expect(middle.subtreeTraits == [.hitTarget])
    }

    @Test func replacingAChildCarriesItsTraitsUp() {
        let middle = ContentNode(content: PaddingContent(insets: .zero), children: [tapNode()])
        let root = ContentNode(content: GroupContent(), children: [middle])

        middle.replaceChild(at: 0, with: ContentNode(content: GroupContent()))
        #expect(middle.subtreeTraits == [.transparent])
        #expect(root.subtreeTraits == [.transparent], "nothing below can be hit any more")

        middle.replaceChild(at: 0, with: hoverNode())
        #expect(root.subtreeTraits == [.transparent, .hoverTarget])
    }
}

/// A hover target that `knobs.isShown` swaps for a plain color.
@View
struct HoverSwap {
    let knobs: Knobs
    let log: Log

    var body: some View {
        VStack(spacing: 0) {
            if knobs.isShown {
                Color.red.frame(width: 100, height: 100).onHover { log("over \($0)") }
            } else {
                Color.blue.frame(width: 100, height: 100)
            }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct HoverTraitTests {

        @Test func aHoverTargetIsFoundAsItComesAndGoes() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(HoverSwap(knobs: knobs, log: log))
            harness.host.pointerMoved(to: Point(x: 100, y: 50))
            #expect(log.take() == ["over true"])

            await harness.change { knobs.isShown = false }
            harness.host.pointerMoved(to: Point(x: 101, y: 50))
            #expect(log.take().isEmpty, "gone with the view, nothing to hover")

            await harness.change { knobs.isShown = true }
            harness.host.pointerMoved(to: Point(x: 100, y: 50))
            #expect(log.take() == ["over true"], "back, it is found again")

            harness.host.pointerMoved(to: Point(x: 190, y: 190))
            #expect(log.take() == ["over false"])
        }
    }
}
