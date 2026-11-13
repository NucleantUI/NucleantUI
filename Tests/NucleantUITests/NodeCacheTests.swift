//
//  NodeCacheTests.swift
//  NucleantUITests
//
//  What a node keeps from one question to the next: the size it gave for
//  each proposal and its flexibility along each axis — asked of its
//  content once, until a change below it drops them.
//

import Testing
@testable import NucleantUI

/// How often a `CountingContent` was asked.
@MainActor
final class Questions {
    var sizes = 0
    var flexibilities = 0
}

/// A leaf that answers from the proposal and counts each question.
struct CountingContent: NodeContent {
    let questions: Questions

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        questions.sizes += 1
        return Size(width: (proposal.width ?? 7) / 2, height: (proposal.height ?? 9) * 3)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {}

    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        questions.flexibilities += 1
        return axis == .horizontal ? .flexible : .fixed
    }
}

@MainActor
@Suite
struct NodeCacheTests {

    private func expected(_ proposal: ProposedSize) -> Size {
        Size(width: (proposal.width ?? 7) / 2, height: (proposal.height ?? 9) * 3)
    }

    /// Proposals a node can be asked, specified and not, finite and not.
    private func proposals(_ count: Int) -> [ProposedSize] {
        (0..<count).map { index in
            switch index % 4 {
            case 0: ProposedSize(width: Double(index), height: 10)
            case 1: ProposedSize(width: nil, height: Double(index))
            case 2: ProposedSize(width: Double(index), height: nil)
            default: ProposedSize(width: .infinity, height: Double(index))
            }
        }
    }

    @Test func eachProposalIsMeasuredOnce() {
        let questions = Questions()
        let node = ViewNode(content: CountingContent(questions: questions))
        let asked = proposals(6) + [.unspecified, .zero, .infinity]
        for proposal in asked {
            #expect(node.sizeThatFits(proposal) == expected(proposal))
        }
        #expect(questions.sizes == asked.count)
        for proposal in asked.reversed() {
            #expect(node.sizeThatFits(proposal) == expected(proposal))
        }
        #expect(questions.sizes == asked.count, "the second time, every answer is the one kept")
    }

    @Test func twentyProposalsAreAllKept() {
        let questions = Questions()
        let node = ViewNode(content: CountingContent(questions: questions))
        let asked = proposals(20)
        for proposal in asked { _ = node.sizeThatFits(proposal) }
        for proposal in asked {
            #expect(node.sizeThatFits(proposal) == expected(proposal))
        }
        #expect(questions.sizes == 20)
    }

    @Test func pastTwentyTheOldestAreAskedAgain() {
        let questions = Questions()
        let node = ViewNode(content: CountingContent(questions: questions))
        let asked = proposals(21)
        for proposal in asked { _ = node.sizeThatFits(proposal) }
        #expect(questions.sizes == 21)
        // The last four are always kept.
        for proposal in asked.suffix(4) {
            #expect(node.sizeThatFits(proposal) == expected(proposal))
        }
        #expect(questions.sizes == 21)
        #expect(node.sizeThatFits(asked[0]) == expected(asked[0]))
        #expect(questions.sizes == 22, "the first was let go to make room")
    }

    @Test func aChangeBelowDropsTheSizesAndTheFlexibilities() {
        let questions = Questions()
        let node = ViewNode(content: CountingContent(questions: questions))
        let asked = proposals(6)
        for proposal in asked { _ = node.sizeThatFits(proposal) }
        #expect(node.flexibility(along: .horizontal) == .flexible)
        #expect(node.flexibility(along: .vertical) == .fixed)
        #expect(node.flexibility(along: .horizontal) == .flexible)
        #expect(node.flexibility(along: .vertical) == .fixed)
        #expect(questions.flexibilities == 2, "once per axis")

        node.invalidateMeasurementsUpwards()
        for proposal in asked {
            #expect(node.sizeThatFits(proposal) == expected(proposal))
        }
        #expect(questions.sizes == 12)
        #expect(node.flexibility(along: .vertical) == .fixed)
        #expect(questions.flexibilities == 3)
    }
}
