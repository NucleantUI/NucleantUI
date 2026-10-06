//
//  Canvas.swift
//  NucleantUI
//
import SulphurGeometry

#if SKIA_MODE

import NucleantSkia



/// A view you draw into with immediate-mode commands.
///
/// ```swift
/// Canvas { context, size in
///     context.fill(Path(ellipseIn: Rect(origin: .zero, size: size)), with: .color(.blue))
/// }
/// .frame(width: 300, height: 200)
/// ```
///
/// A canvas has no pixels of its own. It sits in the render node of the view
/// it is part of — the window's, a `.drawingGroup()`'s — and its renderer
/// draws on that node's Skia canvas, in place, in paint order with the views
/// around it. The context is the handle on it: ``GraphicsContext/canvas`` is
/// the `SkCanvas` itself, and `fill`, `stroke` and the rest are SwiftUI's
/// calls on top.
///
/// The renderer runs when the node is drawn. A `@State` or `@Observable`
/// property it reads makes the canvas redraw when that changes; nothing read
/// changed ⇒ the renderer does not run. Like a `Shape`, a canvas takes
/// whatever space it is offered.
///
/// Unlike SwiftUI's, a canvas has no `symbols`, so it is not generic.
/// `opaque`, `colorMode` and `rendersAsynchronously` are kept for source
/// compatibility and do not change how it draws. It needs the Skia build
/// (`SKIA_MODE`, the default); a ThorVG build does not have it.
@View
public struct Canvas {
    /// The drawing callback.
    ///
    /// - Parameters:
    ///   - context: The graphics context to draw into.
    ///   - size: The current size of the view.
    public var renderer: (inout GraphicsContext, Size) -> Void

    public var isOpaque: Bool
    public var colorMode: ColorRenderingMode
    public var rendersAsynchronously: Bool

    public init(
        opaque: Bool = false,
        colorMode: ColorRenderingMode = .nonLinear,
        rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, Size) -> Void
    ) {
        self.isOpaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
        self.renderer = renderer
    }

    public var body: Never { bodyUnavailable() }
}

extension Canvas: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        ViewNode(content: CanvasContent(path: context.path, renderer: renderer))
    }
}

/// Puts a `.canvas` command in the list at `place`; the node's renderer runs
/// the author's closure when it reaches it.
struct CanvasContent: NodeContent {
    let path: [Int]
    let renderer: (inout GraphicsContext, Size) -> Void
    /// Which build this content came from. A rebuilt view gets a new
    /// content and so a new generation, which is what makes its command
    /// differ from the last pass's and the node redraw.
    let generation: Int = CanvasContent.nextGeneration()

    private static var generations = 0

    private static func nextGeneration() -> Int {
        generations += 1
        return generations
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0 else { return }
        let path = self.path
        let renderer = self.renderer
        let size = rect.size
        let scheme = context.colorScheme
        list.append(.canvas(CanvasDraw(
            frame: rect,
            opacity: context.opacity,
            transform: context.transform,
            clip: context.clip,
            clipCornerRadius: context.clipCornerRadius,
            generation: generation,
            drawing: CanvasDrawing { pointer in
                var graphics = GraphicsContext(canvas: SkCanvas(base: pointer), size: size, colorScheme: scheme)
                // Reads inside the renderer belong to this view: a change
                // to one dirties it alone, which rebuilds it, which draws
                // the node again.
                DependencyTracker.shared.push(path)
                trackingObservation(at: path) {
                    renderer(&graphics, size)
                }
                DependencyTracker.shared.pop()
                _ = DependencyTracker.shared.takeReads(for: path)
            }
        )))
    }
}

#endif
