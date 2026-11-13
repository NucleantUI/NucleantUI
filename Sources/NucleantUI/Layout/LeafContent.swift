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
    let style: _ResolvedPaint
    let alignment: TextAlignment
    let underline: Text.LineStyle?
    let strikethrough: Text.LineStyle?
    /// `style`, animated — a change of foreground color fades across.
    var animatedColor: AnimatedVector? = nil

    /// Laid out at its final size throughout, never reflowed mid-way.
    var animatesSize: Bool { false }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        layout(for: proposal, node: node).size
    }

    /// The layout under `proposal`: the one kept on the node, when it was
    /// made under the same — placing follows measuring under the proposal
    /// just measured, and a pass that only places asks for it again —
    /// or the measurer's, kept.
    private func layout(for proposal: ProposedSize, node: ViewNode) -> TextLayout {
        if let kept = node.layoutCache as? TextLayoutCache, kept.proposal == proposal {
            return kept.layout
        }
        let layout = TextMeasurer.layout(input, proposal: proposal)
        node.layoutCache = TextLayoutCache(proposal: proposal, layout: layout)
        return layout
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
        var layout = self.layout(for: proposal, node: node)
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
            lines: layout.lines,
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

/// A text node's last layout, and the proposal it was made under.
@MainActor
final class TextLayoutCache {
    let proposal: ProposedSize
    let layout: TextLayout

    init(proposal: ProposedSize, layout: TextLayout) {
        self.proposal = proposal
        self.layout = layout
    }
}

/// A filled and/or stroked shape, of its own type.
struct ShapeContent<S: Shape>: NodeContent {
    let shape: S
    /// The shape as an animation of its data has it at the moment of
    /// drawing, while one is on its way; `nil` when it is drawn as it is.
    let drawn: (@MainActor () -> S)?
    let fill: _ResolvedPaint?
    let stroke: _ResolvedPaint?
    let strokeStyle: StrokeStyle
    /// A shape claims whatever it is offered; an unspecified axis collapses to
    /// nothing, matching SwiftUI (a `Circle()` in a `VStack` with no width
    /// proposal is empty, not infinite).
    let idealSize: Size?
    /// `fill` and `stroke`, animated — see `BuildContext.animatedPaint`.
    var animatedFill: AnimatedVector? = nil
    var animatedStroke: AnimatedVector? = nil

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions(by: idealSize ?? .zero)
    }

    /// The path in the shape's own space, at `rect`'s origin in the list —
    /// so the same shape at the same size has the same path wherever it
    /// lands, and a move of it changes the origin and nothing else.
    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0 else { return }
        guard fill != nil || stroke != nil else { return }
        let own = Rect(origin: .zero, size: rect.size)
        let (path, pathBox) = path(in: own, node: node)
        list.append(.shape(ShapeDraw(
            path: path,
            pathBox: pathBox,
            bounds: own,
            fill: fill.map { context.resolve(animatedFill?.current(of: $0) ?? $0) },
            stroke: stroke.map { context.resolve(animatedStroke?.current(of: $0) ?? $0) },
            strokeStyle: strokeStyle,
            transform: context.transform,
            clip: context.clip,
            clipCornerRadius: context.clipCornerRadius,
            transformedClips: context.transformedClips,
            origin: rect.origin
        )))
    }

    /// The shape's path in `rect`, its own, and the path's box: the ones
    /// made last, kept on the node, when they were made at the same size;
    /// made at each frame's value while the shape's data is on its way.
    private func path(in rect: Rect, node: ViewNode) -> (Path, Rect?) {
        if let drawn {
            let path = drawn().path(in: rect)
            return (path, path.boundingBox)
        }
        if let kept = node.layoutCache as? ShapePathCache, kept.size == rect.size {
            return (kept.path, kept.box)
        }
        let kept = ShapePathCache(size: rect.size, path: shape.path(in: rect))
        node.layoutCache = kept
        return (kept.path, kept.box)
    }
}

/// A shape node's last path, the size it was made at, and its box.
@MainActor
final class ShapePathCache {
    let size: Size
    let path: Path
    let box: Rect?

    init(size: Size, path: Path) {
        self.size = size
        self.path = path
        self.box = path.boundingBox
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


