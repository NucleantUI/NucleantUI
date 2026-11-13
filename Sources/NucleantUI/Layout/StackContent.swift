//
//  StackContent.swift
//  NucleantUI
//
//  The stack layout, sized the way SwiftUI's stacks are: children in order of
//  flexibility — how far each stretches along the axis, from what it takes
//  when offered nothing to what it takes when offered everything — the least
//  flexible first, each offered an equal share of what the ones before it
//  left. A fixed `.frame` takes its own size first; texts follow, the shorter
//  first, so a row that fits puts each at its natural width, and one that
//  doesn't squeezes the longest; a `Spacer`, stretching without end, comes
//  last and gets what is left. `HStack { Text("a"); Spacer(); Text("b") }`
//  puts the texts at their natural widths and the rest in the spacer.
//

struct StackContent: NodeContent {
    let axis: Axis
    /// `nil` means "the default gap", resolved at layout time.
    let spacing: Double?
    let horizontalAlignment: HorizontalAlignment
    let verticalAlignment: VerticalAlignment

    static let defaultSpacing: Double = 8

    private var resolvedSpacing: Double { spacing ?? Self.defaultSpacing }

    /// As flexible as the most flexible child: a row of fixed frames is fixed
    /// and must be sized before a sibling `Text`; one holding a `Spacer`
    /// soaks up whatever is left.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        var most: LayoutPriorityClass?
        for child in node.layoutChildren {
            let flexibility = child.flexibility(along: axis)
            if most.map({ flexibility > $0 }) ?? true { most = flexibility }
        }
        return most ?? .content
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        layout(proposal, node: node, children: node.layoutChildren).total
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let children = node.layoutChildren
        guard !children.isEmpty else { return }

        // Laid out again under the proposal the stack was sized by along its
        // axis, as SwiftUI does, so each child gets the share it was measured
        // with — the rect is the stack's own size, and a share of that can
        // come out differently. Across the axis, the rect's extent when none
        // was proposed. Each child is then placed with the very proposal it
        // was measured under, which `layout` hands back.
        let crossAxis = axis.cross
        var placing = proposal
        placing[crossAxis] = proposal[crossAxis] ?? rect.size[crossAxis]
        let result = layout(placing, node: node, children: children)

        // Extra room along the main axis when the children ended up smaller
        // than the rect (a stack of fixed-size views inside a bigger frame).
        let leftover = max(0, rect.size[axis] - result.total[axis])
        var cursor = rect.origin[axis] + mainAxisOffset(forLeftover: leftover)

        for (index, child) in children.enumerated() {
            let size = result.sizes[index]
            var origin = Point.zero
            origin[axis] = cursor
            origin[crossAxis] = rect.origin[crossAxis]
                + crossOffset(childExtent: size[crossAxis], containerExtent: rect.size[crossAxis])
            child.place(
                in: Rect(origin: origin, size: size),
                proposal: result.proposals[index],
                context: context,
                into: &list
            )
            cursor += size[axis] + resolvedSpacing
        }
    }

    /// Where the whole run of children starts when they don't fill the rect —
    /// governed by the *cross*-axis alignment's counterpart on the main axis,
    /// which for a stack is always centring in SwiftUI.
    private func mainAxisOffset(forLeftover leftover: Double) -> Double {
        switch axis {
        case .vertical:   return verticalAlignment.offset(childHeight: 0, in: leftover)
        case .horizontal: return horizontalAlignment.offset(childWidth: 0, in: leftover)
        }
    }

    private func crossOffset(childExtent: Double, containerExtent: Double) -> Double {
        switch axis {
        case .vertical:
            return horizontalAlignment.offset(childWidth: childExtent, in: containerExtent)
        case .horizontal:
            return verticalAlignment.offset(childHeight: childExtent, in: containerExtent)
        }
    }

    // MARK: - The measuring pass

    struct LayoutResult {
        /// The proposal the stack was laid out under.
        var proposal: ProposedSize
        var sizes: [Size]
        /// The proposal each child was measured under — carried so placement
        /// can reuse it instead of re-deriving one from the child's own size.
        var proposals: [ProposedSize]
        var total: Size
    }

    /// The run under `proposal`: the last one, when it was laid out under
    /// the same — `place` lays the stack out again under the proposal it
    /// was just measured with — or worked out and kept.
    private func layout(_ proposal: ProposedSize, node: ViewNode, children: [ViewNode]) -> LayoutResult {
        let cache: StackRunCache
        if let existing = node.stackCache {
            cache = existing
            if let last = cache.run, last.proposal == proposal, last.sizes.count == children.count {
                return last
            }
        } else {
            cache = StackRunCache()
            node.stackCache = cache
        }
        let result = layout(proposal, children: children, cache: cache)
        cache.run = result
        return result
    }

    private func layout(_ proposal: ProposedSize, children: [ViewNode], cache: StackRunCache) -> LayoutResult {
        guard !children.isEmpty else {
            return LayoutResult(proposal: proposal, sizes: [], proposals: [], total: .zero)
        }

        let crossAxis = axis.cross
        let totalSpacing = resolvedSpacing * Double(children.count - 1)

        var sizes = [Size](repeating: .zero, count: children.count)
        var proposals = [ProposedSize](repeating: proposal, count: children.count)

        if var remaining = proposal[axis].map({ max(0, $0 - totalSpacing) }) {
            // Least flexible first, each offered an equal share of what the
            // ones before it left — not the whole of it, or the first child
            // that takes all it is offered leaves nothing for the rest.
            for (position, index) in fittingOrder(children, proposal: proposal, cache: cache).enumerated() {
                var childProposal = proposal
                childProposal[axis] = remaining / Double(children.count - position)
                let size = children[index].sizeThatFits(childProposal)
                sizes[index] = size
                proposals[index] = childProposal
                remaining = max(0, remaining - size[axis])
            }
        } else {
            // Nobody constrains the stack along its axis, so each child
            // sizes itself.
            for (index, child) in children.enumerated() {
                sizes[index] = child.sizeThatFits(proposal)
            }
        }

        var total = Size.zero
        total[axis] = sizes.reduce(0) { $0 + $1[axis] } + totalSpacing
        total[crossAxis] = sizes.reduce(0) { max($0, $1[crossAxis]) }
        // Never claim more than was offered — a stack that overflowed still
        // reports the box it was given, and its children simply spill. The
        // exception is a run of fixed children: that is as immovable as a
        // fixed `.frame`, and reports its true extent so the stack around it
        // sizes the rest around *that* rather than around an equal share.
        let isFixedRun = children.allSatisfy { $0.flexibility(along: axis) == .fixed }
        if let limit = proposal[axis], !isFixedRun { total[axis] = min(total[axis], max(limit, 0)) }
        if let limit = proposal[crossAxis] { total[crossAxis] = min(total[crossAxis], max(limit, 0)) }

        return LayoutResult(proposal: proposal, sizes: sizes, proposals: proposals, total: total)
    }

    /// The order the children are offered space in, as SwiftUI's stacks
    /// offer it: the least flexible first. A child's flexibility is how far
    /// it stretches along the axis, from its length when offered none to its
    /// length when offered all there is; among those that stretch without
    /// end, the one that needs more goes first. Ties keep the children's
    /// own order.
    ///
    /// One child has no order to find. How far a child stretches depends
    /// on what is proposed across the axis, not along it, so the ranges are
    /// kept for that proposal: a stack measured again at another length —
    /// probed by the stack around it, or a window resized along it — sorts
    /// its children without asking them again.
    private func fittingOrder(_ children: [ViewNode], proposal: ProposedSize, cache: StackRunCache) -> [Int] {
        guard children.count > 1 else { return Array(children.indices) }
        let cross = proposal[axis.cross]
        let ranges: [(min: Double, span: Double)]
        if let kept = cache.stretch, kept.cross == cross, kept.ranges.count == children.count {
            ranges = kept.ranges
        } else {
            var least = proposal
            least[axis] = 0
            var most = proposal
            most[axis] = .infinity
            ranges = children.map { child -> (min: Double, span: Double) in
                let min = child.sizeThatFits(least)[axis]
                return (min, child.sizeThatFits(most)[axis] - min)
            }
            cache.stretch = (cross, ranges)
        }
        func precedes(_ a: Int, _ b: Int) -> Bool {
            guard ranges[a].span == ranges[b].span else { return ranges[a].span < ranges[b].span }
            return ranges[a].span == .infinity && ranges[a].min > ranges[b].min
        }
        // An insertion sort: stable, and a stack's children are few.
        var order = Array(children.indices)
        for next in order.indices.dropFirst() {
            var position = next
            while position > 0, precedes(order[position], order[position - 1]) {
                order.swapAt(position, position - 1)
                position -= 1
            }
        }
        return order
    }
}

/// What a stack's node keeps between questions, until the node's
/// measurements are dropped or its children change: the last run it laid
/// out, and how far each child stretches along the axis under the last
/// cross-axis proposal.
@MainActor
final class StackRunCache {
    var run: StackContent.LayoutResult?
    var stretch: (cross: Double?, ranges: [(min: Double, span: Double)])?
}

/// Depth-stacked children, all sharing one rect.
struct ZStackContent: NodeContent {
    let alignment: Alignment

    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        node.layoutChildren.map { $0.flexibility(along: axis) }.max() ?? .content
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        var result = Size.zero
        for child in node.layoutChildren {
            let size = child.sizeThatFits(proposal)
            result.width = max(result.width, size.width)
            result.height = max(result.height, size.height)
        }
        return result
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        // Every child of a ZStack is offered the whole rect, so that proposal
        // is both what sizes it and what it is placed under.
        let childProposal = ProposedSize(rect.size)
        for child in node.layoutChildren {
            let size = child.sizeThatFits(childProposal)
            child.place(
                in: alignment.position(size, in: rect),
                proposal: childProposal,
                context: context,
                into: &list
            )
        }
    }
}
