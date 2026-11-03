//
//  SvgView.swift
//  NucleantUI
//

/// A view that draws an SVG document.
///
/// ```swift
/// let icon = SvgImage(contentsOf: url)!
/// SvgView(icon)                                 // at the document's own size
/// SvgView(icon).resizable().frame(width: 64)    // as large as it is offered
/// SvgView(icon)
///     .renderingMode(.template)                 // in the foreground style
///     .foregroundStyle(.blue)
/// ```
///
/// A document is drawn at its own size unless it is `.resizable()`, which
/// takes whatever it is offered. Either way it keeps its proportions: the
/// picture is as large as fits in the view's frame, centered in it — what
/// an `<svg>` does in a browser. `.aspectRatio(contentMode:)` /
/// `.scaledToFit()` make the frame itself take the document's proportions.
@View
public struct SvgView {
    public let image: SvgImage
    var isResizable = false
    var renderingMode: TemplateRenderingMode?

    public init(_ image: SvgImage, _viewID: ViewID = #viewID) {
        self.image = image
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }

    /// Sized to the proposal instead of drawn at the document's own size.
    public func resizable() -> SvgView {
        var copy = self
        copy.isResizable = true
        return copy
    }

    /// `.template` paints the document in the foreground style; `.original`
    /// or `nil` draws its own colors.
    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> SvgView {
        var copy = self
        copy.renderingMode = renderingMode
        return copy
    }
}

extension SvgView {
    /// How an `SvgView` colors what it draws.
    public enum TemplateRenderingMode: Hashable, Sendable {
        /// Everything the document draws painted in the foreground style,
        /// each part by its own coverage and opacity — an icon taking the
        /// color of the text around it.
        case template
        /// The document's own colors.
        case original
    }
}

extension SvgView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        ViewNode(content: SvgContent(
            image: image,
            isResizable: isResizable,
            tint: renderingMode == .template ? context.environment.foregroundStyle : nil
        ))
    }
}

/// `SvgView`.
struct SvgContent: NodeContent {
    let image: SvgImage
    let isResizable: Bool
    /// The style a template is painted in; `nil` for the document's own
    /// colors.
    let tint: ShapeStyle?

    /// Fixed at the document's size; resizable, it takes what it is offered
    /// and the document's size on an axis nobody constrained.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        isResizable ? .flexible : .fixed
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        isResizable ? proposal.replacingUnspecifiedDimensions(by: image.size) : image.size
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0 else { return }
        list.append(.svg(SvgDraw(
            image: image,
            frame: rect,
            tint: tint?.resolved(for: context.colorScheme),
            opacity: context.opacity,
            transform: context.transform,
            clip: context.clip,
            clipCornerRadius: context.clipCornerRadius,
            transformedClips: context.transformedClips
        )))
    }
}
