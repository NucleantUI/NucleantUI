//
//  LeafContent.swift
//  NucleantUI
//
//  The nodes that actually put something in the display list.
//

/// `Text`.
struct TextContent: NodeContent {
    /// The string, its font and the paragraph settings: everything its lines
    /// depend on, and what its layouts are kept by.
    let input: TextLayoutInput
    /// Drawn as one flat color: a gradient gives its first stop.
    let style: ShapeStyle
    let alignment: TextAlignment
    let underline: Text.LineStyle?
    let strikethrough: Text.LineStyle?
    /// `style`, animated — a change of foreground color fades across.
    var animatedColor: AnimatedVector? = nil

    /// Laid out at its final size throughout, never reflowed mid-way.
    var animatesSize: Bool { false }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        TextMeasurer.layout(input, proposal: proposal).size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard !input.string.isEmpty else { return }
        // The lines sizing found (the same proposal, so the same layout),
        // drawn as they are and never broken again: ThorVG, whose advances
        // come out a fraction wider, would break a line that just fits once
        // more, and draw a line more than the box has room for. Only in a
        // box a parent squeezed below what the text asked for are they made
        // again, for the box. The half-point slack absorbs the difference
        // between summed glyph advances here and ThorVG's own layout.
        var layout = TextMeasurer.layout(input, proposal: proposal)
        if layout.size.width > rect.width + 0.5 || layout.size.height > rect.height + 0.5 {
            layout = TextMeasurer.layout(input, proposal: ProposedSize(
                width: min(proposal.width ?? .infinity, rect.width + 0.5),
                height: min(proposal.height ?? .infinity, rect.height + 0.5)
            ))
        }

        // The glyphs' own box: the text's box without the room the baseline
        // offset added, which is on the side the glyphs moved away from.
        let offset = input.baselineOffset
        var frame = rect
        frame.size.height = max(0, rect.height - abs(offset))
        if offset < 0 { frame.origin.y -= offset }

        let font = layout.scale == 1 ? input.font : input.font.size(input.font.size * layout.scale)
        list.append(.text(TextDraw(
            string: layout.lines.joined(separator: "\n"),
            frame: frame,
            font: font,
            color: context.resolve(animatedColor?.current(of: style) ?? style).flatColor,
            alignment: alignment,
            // Already broken, limited and cut: a line too long carries its
            // ellipsis.
            wraps: false,
            letterSpacing: input.letterSpacing,
            lastLineTightening: layout.lastLineTightening,
            lineSpacing: max(input.paragraph.lineSpacing, 0),
            underline: underline.map { Text.LineStyle(pattern: $0.pattern, color: $0.color.map(context.resolve)) },
            strikethrough: strikethrough.map { Text.LineStyle(pattern: $0.pattern, color: $0.color.map(context.resolve)) },
            transform: context.transform,
            clip: context.clip,
            clipCornerRadius: context.clipCornerRadius,
            transformedClips: context.transformedClips
        )))
    }
}

/// A filled and/or stroked shape. The shape itself is a closure so every
/// concrete `Shape` reduces to one node kind.
struct ShapeContent: NodeContent {
    /// Builds the path in *local* coordinates for a given size.
    let makePath: (Rect) -> Path
    let fill: ShapeStyle?
    let stroke: ShapeStyle?
    let strokeStyle: StrokeStyle
    /// A shape claims whatever it is offered; an unspecified axis collapses to
    /// nothing, matching SwiftUI (a `Circle()` in a `VStack` with no width
    /// proposal is empty, not infinite).
    let idealSize: Size?
    /// `fill` and `stroke`, animated — see `BuildContext.animatedStyle`.
    var animatedFill: AnimatedVector? = nil
    var animatedStroke: AnimatedVector? = nil

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions(by: idealSize ?? .zero)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0 else { return }
        guard fill != nil || stroke != nil else { return }
        list.append(.shape(ShapeDraw(
            path: makePath(rect),
            bounds: rect,
            fill: fill.map { context.resolve(animatedFill?.current(of: $0) ?? $0) },
            stroke: stroke.map { context.resolve(animatedStroke?.current(of: $0) ?? $0) },
            strokeStyle: strokeStyle,
            transform: context.transform,
            clip: context.clip,
            clipCornerRadius: context.clipCornerRadius,
            transformedClips: context.transformedClips
        )))
    }
}

/// `Spacer` — takes every point the stack will give it along its axis.
struct SpacerContent: NodeContent {
    let minLength: Double
    /// Set by the stack when it places the spacer; `nil` outside a stack, where
    /// a spacer expands on both axes.
    let axis: Axis?

    /// Flexible along its stack's axis, and nothing at all across it — a
    /// spacer in an `HStack` has no height, so the row it is in must not
    /// look vertically flexible to the stack around that row.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        guard let own = self.axis else { return .flexible }
        return axis == own ? .flexible : .fixed
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        var size = Size(width: minLength, height: minLength)
        switch axis {
        case .horizontal:
            size.width = max(minLength, proposal.width ?? minLength)
            size.height = 0
        case .vertical:
            size.height = max(minLength, proposal.height ?? minLength)
            size.width = 0
        case nil:
            size = proposal.replacingUnspecifiedDimensions(by: size)
        }
        return size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {}
}

/// The layout flexibility a stack sorts by. A spacer is maximally flexible, a
/// fixed frame not at all — sizing the least flexible children first is what
/// keeps a `Text` from being squeezed by a greedy sibling.
enum LayoutPriorityClass: Int, Comparable {
    case fixed = 0
    case content = 1
    case flexible = 2

    static func < (lhs: LayoutPriorityClass, rhs: LayoutPriorityClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}


