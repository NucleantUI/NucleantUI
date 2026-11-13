//
//  StackLayouts.swift
//  NucleantUI
//
//  The stacks as `Layout` values — `HStackLayout`, `VStackLayout`,
//  `ZStackLayout` — for use where a layout is a value: `AnyLayout`, to
//  switch between them without the subviews losing their state, or inside
//  another `Layout`. Written against `LayoutSubviews`, and sizing the same
//  way the stack views do, which is SwiftUI's: least flexible first, each
//  offered an equal share of what the ones before it left.
//

/// A horizontal stack as a `Layout`.
public struct HStackLayout: Layout, Sendable {
    public var alignment: VerticalAlignment
    public var spacing: Double?

    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> Size {
        StackLayoutRun(axis: .horizontal, spacing: spacing, subviews: subviews, proposal: proposal).total
    }

    public func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Laid out again under the proposal it was sized by along its axis,
        // as SwiftUI does, so the subviews get the shares they were measured
        // with; across it, the bounds' height when none was proposed.
        let placing = ProposedViewSize(width: proposal.width, height: proposal.height ?? bounds.height)
        let run = StackLayoutRun(axis: .horizontal, spacing: spacing, subviews: subviews, proposal: placing)
        var x = bounds.minX
        for (offset, subview) in subviews.enumerated() {
            let size = run.sizes[offset]
            let y: Double
            switch alignment {
            case .top:    y = bounds.minY
            case .center: y = bounds.minY + (bounds.height - size.height) / 2
            case .bottom: y = bounds.maxY - size.height
            }
            subview.place(at: Point(x: x, y: y), proposal: run.proposals[offset])
            x += size.width + run.gaps[offset]
        }
    }
}

/// A vertical stack as a `Layout`.
public struct VStackLayout: Layout, Sendable {
    public var alignment: HorizontalAlignment
    public var spacing: Double?

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .vertical
        return properties
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> Size {
        StackLayoutRun(axis: .vertical, spacing: spacing, subviews: subviews, proposal: proposal).total
    }

    public func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Laid out again under the proposal it was sized by along its axis,
        // as SwiftUI does; across it, the bounds' width when none was proposed.
        let placing = ProposedViewSize(width: proposal.width ?? bounds.width, height: proposal.height)
        let run = StackLayoutRun(axis: .vertical, spacing: spacing, subviews: subviews, proposal: placing)
        var y = bounds.minY
        for (offset, subview) in subviews.enumerated() {
            let size = run.sizes[offset]
            let x: Double
            switch alignment {
            case .leading:  x = bounds.minX
            case .center:   x = bounds.minX + (bounds.width - size.width) / 2
            case .trailing: x = bounds.maxX - size.width
            }
            subview.place(at: Point(x: x, y: y), proposal: run.proposals[offset])
            y += size.height + run.gaps[offset]
        }
    }
}

/// Overlaid subviews as a `Layout`, each offered the whole bounds.
public struct ZStackLayout: Layout, Sendable {
    public var alignment: Alignment

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> Size {
        var result = Size.zero
        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            result.width = max(result.width, size.width)
            result.height = max(result.height, size.height)
        }
        return result
    }

    public func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let offered = ProposedViewSize(bounds.size)
        // The point of each subview that sits on the same point of the
        // bounds: its top-leading corner for `.topLeading`, and so on.
        let x: Double = switch alignment.horizontal {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let y: Double = switch alignment.vertical {
        case .top: 0
        case .center: 0.5
        case .bottom: 1
        }
        let anchor = UnitPoint(x: x, y: y)
        for subview in subviews {
            subview.place(at: anchor.resolved(in: bounds), anchor: anchor, proposal: offered)
        }
    }
}

// MARK: - The stack run

/// One measuring pass of a horizontal or vertical stack layout: the size
/// and proposal of every subview, the gap after each, and the total.
@MainActor
private struct StackLayoutRun {
    var sizes: [Size]
    var proposals: [ProposedSize]
    /// The gap after each subview — zero after the last.
    var gaps: [Double]
    var total: Size

    init(axis: Axis, spacing: Double?, subviews: LayoutSubviews, proposal: ProposedSize) {
        let count = subviews.count
        let items = Array(subviews)
        sizes = Array(repeating: .zero, count: count)
        proposals = Array(repeating: proposal, count: count)
        gaps = Array(repeating: 0, count: count)
        total = .zero
        guard count > 0 else { return }

        for index in 0..<(count - 1) {
            gaps[index] = spacing ?? items[index].spacing.distance(to: items[index + 1].spacing, along: axis)
        }
        let totalSpacing = gaps.reduce(0, +)
        let flexibility = items.map { $0.node.flexibility(along: axis) }

        if var remaining = proposal[axis].map({ max(0, $0 - totalSpacing) }) {
            // The least flexible first — how far each stretches along the
            // axis, from offered nothing to offered everything; among those
            // that stretch without end, the one needing more first; ties in
            // the subviews' own order — each offered an equal share of what
            // the ones before it left.
            var least = proposal
            least[axis] = 0
            var most = proposal
            most[axis] = .infinity
            let ranges = items.map { item -> (min: Double, span: Double) in
                let min = item.sizeThatFits(least)[axis]
                return (min, item.sizeThatFits(most)[axis] - min)
            }
            var order = Array(0..<count)
            for next in order.indices.dropFirst() {
                var position = next
                while position > 0 {
                    let (a, b) = (ranges[order[position]], ranges[order[position - 1]])
                    let precedes = a.span == b.span ? a.span == .infinity && a.min > b.min : a.span < b.span
                    guard precedes else { break }
                    order.swapAt(position, position - 1)
                    position -= 1
                }
            }
            for (position, index) in order.enumerated() {
                var offered = proposal
                offered[axis] = remaining / Double(count - position)
                let size = items[index].sizeThatFits(offered)
                sizes[index] = size
                proposals[index] = offered
                remaining = max(0, remaining - size[axis])
            }
        } else {
            for index in 0..<count {
                sizes[index] = items[index].sizeThatFits(proposal)
            }
        }

        let cross = axis.cross
        total[axis] = sizes.reduce(0) { $0 + $1[axis] } + totalSpacing
        total[cross] = sizes.reduce(0) { max($0, $1[cross]) }
        // Never more than offered, unless every subview is fixed — then the
        // run is as immovable as they are.
        let isFixedRun = flexibility.allSatisfy { $0 == .fixed }
        if let limit = proposal[axis], !isFixedRun { total[axis] = min(total[axis], max(limit, 0)) }
        if let limit = proposal[cross] { total[cross] = min(total[cross], max(limit, 0)) }
    }
}
