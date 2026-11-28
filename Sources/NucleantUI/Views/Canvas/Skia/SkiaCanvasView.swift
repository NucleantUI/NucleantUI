//
//  SkiaCanvasView.swift
//  NucleantUI
//
import NucleantSkia

/// A view drawn with the Skia API itself, by a `SkiaRenderContext`.
///
/// ```swift
/// SkiaCanvasView(context: instructions)   // a SkiaRenderContext
/// ```
///
/// No pixels of its own: the object draws on the Skia canvas the views
/// around it are drawn on — the window's, a `.drawingGroup()`'s — in place,
/// in paint order with them, as a `Canvas` does. Its callbacks are handed
/// that canvas at the view's origin, cut to its frame, under its clip,
/// transform and opacity, in points.
///
/// `onAppear` runs once, in the view's first draw; `update` after it, and
/// again whenever the canvas is drawn. A `@State` read through a captured
/// binding, or an `@Observable` property read, inside `update` makes this
/// view depend on it: a change rebuilds this view alone and draws the canvas
/// again. The object is compared by identity, so the parent rebuilding with
/// the same object changes nothing here. `id` starts over: a different value
/// runs `onAppear` again. Like a `Shape`, the view takes whatever space it
/// is offered.
@View
public struct SkiaCanvasView<Context: SkiaRenderContext> {
    let nodeID: Int
    let context: Context

    public init(context: Context, _viewID: ViewID = #viewID) {
        self.nodeID = _viewID.hash
        self.context = context
        self._viewID = _viewID
    }

    public init<ID: Hashable>(id: ID, context: Context, _viewID: ViewID = #viewID) {
        self.nodeID = id.hashValue
        self.context = context
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }
}

extension SkiaCanvasView: BuiltinView {
    func makeNode(_ build: inout BuildContext) -> ViewNode {
        let context = self.context
        return ContentNode(content: SkiaCanvasContent(
            key: RenderNodeKey(slot: build.position.renderSlot, identity: build.viewIdentity, id: nodeID),
            reader: build.position.handle,
            onAppear: { canvas, size in context.onAppear(context: canvas, size: size) },
            update: { canvas, size in context.update(context: canvas, size: size) }
        ))
    }
}

/// Puts a `.canvas` command in the list at `place`; the renderer hands the
/// author's callbacks its canvas when it reaches it.
struct SkiaCanvasContent: NodeContent {
    /// Which view this is, and its `id`: what `onAppear` runs once for.
    let key: RenderNodeKey
    /// Whose reads what `update` reads are: the view's.
    let reader: PositionHandle
    let onAppear: (borrowing SkCanvas, SIMD2<Float>) -> Void
    let update: (borrowing SkCanvas, SIMD2<Float>) -> Void
    /// Which build this content came from. A rebuilt view gets a new
    /// content and so a new generation, which is what makes its command
    /// differ from the last pass's and the canvas redraw. Counted down from
    /// -1, so it is never a `Canvas`'s (counted up from 1): one of each
    /// swapped at the same spot is a different command.
    let generation: Int = SkiaCanvasContent.nextGeneration()

    private static var generations = 0

    private static func nextGeneration() -> Int {
        generations -= 1
        return generations
    }

    /// The views that have run `onAppear`, one key each, while they stand.
    private static var appeared: Set<RenderNodeKey> = []

    /// Whether the view at `key` runs `onAppear` now: the first time it is
    /// drawn, and again after its `id` changed. A view that left the tree
    /// takes its slot with it, so one that comes back appears again; the
    /// keys of views gone are dropped here.
    private static func appears(_ key: RenderNodeKey) -> Bool {
        guard !appeared.contains(key) else { return false }
        appeared = appeared.filter { standing in
            standing.slot.standingPosition != nil
                && !(standing.slot == key.slot && standing.identity == key.identity)
        }
        appeared.insert(key)
        return true
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0 else { return }
        let key = self.key
        let reader = self.reader
        let onAppear = self.onAppear
        let update = self.update
        let size = SIMD2<Float>(Float(rect.width), Float(rect.height))
        list.append(.canvas(CanvasDraw(
            frame: rect,
            opacity: context.opacity,
            generation: generation,
            drawing: CanvasDrawing { pointer in
                let canvas = SkCanvas(base: pointer)
                if SkiaCanvasContent.appears(key) {
                    onAppear(canvas, size)
                }
                // Reads inside `update` belong to this view: a change to one
                // dirties it alone, which rebuilds it, which draws the
                // canvas again.
                DependencyTracker.shared.push(reader)
                trackingObservation(for: reader) {
                    update(canvas, size)
                }
                DependencyTracker.shared.pop()
            }
        )), under: context.drawState)
    }
}
