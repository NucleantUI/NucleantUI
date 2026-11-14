//
//  MeasuresLikeTests.swift
//  NucleantUITests
//
//  A node swapped in by a scoped rebuild that gives every size the old one
//  was asked, and is as flexible, leaves the sizes cached above it standing.
//

import Testing
@testable import NucleantUI

/// How often a `Measured` leaf was asked its size.
private final class Asked {
    var count = 0
}

/// A leaf of a pure kind with a fixed size, counting the questions.
private struct Measured: NodeContent {
    static var placesPurely: Bool { true }
    let size: Size
    let asked: Asked

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        asked.count += 1
        return size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {}
}

/// A leaf of a kind that does not say it places purely.
private struct Opaque: NodeContent {
    let size: Size

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size { size }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {}
}

@MainActor
@Suite
struct MeasuresLikeTests {

    private let square = Size(width: 20, height: 20)

    private func leaf(_ size: Size, _ asked: Asked = Asked()) -> ViewNode {
        ContentNode(content: Measured(size: size, asked: asked))
    }

    private func padded(_ child: ViewNode) -> ViewNode {
        ContentNode(content: PaddingContent(insets: EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)), children: [child])
    }

    @Test func theSameSizesToEveryQuestionMeasureAlike() {
        let old = leaf(square)
        _ = old.sizeThatFits(ProposedSize(width: 100, height: 100))
        _ = old.sizeThatFits(.unspecified)
        let asked = Asked()
        let replacement = leaf(square, asked)
        #expect(replacement.measuresLike(old))
        #expect(asked.count == 2, "asked what the old one was asked, and no more")
        #expect(!leaf(Size(width: 30, height: 20)).measuresLike(old), "another size")
    }

    @Test func aTransparentOrAnImpureOneIsNotCompared() {
        let old = leaf(square)
        _ = old.sizeThatFits(.unspecified)
        let group = ContentNode(content: GroupContent(), children: [leaf(square)])
        #expect(!group.measuresLike(old), "dissolves into its parent's children")
        let unpadded = ContentNode(content: PaddingContent(insets: .zero), children: [leaf(square)])
        #expect(unpadded.measuresLike(old), "another kind, the same sizes: the sizes above hold")
        let opaque = ContentNode(content: Opaque(size: square))
        _ = opaque.sizeThatFits(.unspecified)
        #expect(!ContentNode(content: Opaque(size: square)).measuresLike(opaque), "not measured outside a pass")
    }

    @Test func answersDroppedToMakeRoomProveNothing() {
        let old = leaf(square)
        for width in 1...24 {
            _ = old.sizeThatFits(ProposedSize(width: Double(width), height: 10))
        }
        #expect(!leaf(square).measuresLike(old))
    }

    @Test func aSwapThatMeasuresAlikeLeavesTheSizesAbove() {
        let old = leaf(square)
        let parent = padded(old)
        let root = padded(parent)
        let proposal = ProposedSize(width: 100, height: 100)
        #expect(root.sizeThatFits(proposal) == Size(width: 24, height: 24))

        let asked = Asked()
        let replacement = leaf(square, asked)
        parent.replaceChild(at: 0, with: replacement)
        #expect(replacement.measuresLike(old))
        parent.invalidatePreferencesUpwards()
        let questions = asked.count
        #expect(root.sizeThatFits(proposal) == Size(width: 24, height: 24))
        #expect(asked.count == questions, "answered from what is cached above")
    }

    @Test func aSwapThatMeasuresOtherwiseIsMeasuredAgain() {
        let old = leaf(square)
        let parent = padded(old)
        let root = padded(parent)
        let proposal = ProposedSize(width: 100, height: 100)
        _ = root.sizeThatFits(proposal)

        let wider = leaf(Size(width: 40, height: 20))
        parent.replaceChild(at: 0, with: wider)
        #expect(!wider.measuresLike(old))
        parent.invalidateMeasurementsUpwards()
        #expect(root.sizeThatFits(proposal) == Size(width: 44, height: 24))
    }
}
