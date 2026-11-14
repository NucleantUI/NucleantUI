//
//  DragSession.swift
//  NucleantUI
//
//  One drag, from the moment the pointer has moved far enough on a
//  `.draggable` to the release. Owned by `ViewHost`, which feeds it pointer
//  positions and asks it to paint the preview after each layout pass.
//

/// A drag in flight: what it carries, what it looks like, where it is, and
/// which destination it is over.
@MainActor
final class DragSession {

    let payload: TransferPayload
    private let preview: Preview

    /// Where the pointer was when the drag began, in window coordinates —
    /// the snapshot preview is drawn where the view was, moved by however
    /// far the pointer has come since.
    let origin: Point
    var location: Point

    /// The destination the pointer is over, if it could take the payload.
    /// Held by path as well as object: a rebuild replaces the object (see
    /// `DropTarget.path`).
    private(set) var target: Hit<DropTarget>?

    /// How the preview is painted — never fully opaque, so what it is over
    /// still shows through.
    private static let previewOpacity = 0.8

    private enum Preview {
        /// The dragged view exactly as it was last drawn, clip removed.
        case snapshot(DisplayList)
        /// A view of the caller's, built for the drag, centred on the pointer.
        case view(ViewNode, size: Size, environment: EnvironmentValues)
    }

    /// `environment` is the one the source's view stands under — a custom
    /// preview is built under it.
    init(source: Hit<DragSource>, origin: Point, environment: EnvironmentValues) {
        payload = source.value.makePayload()
        self.origin = origin
        location = origin

        if let makePreview = source.value.makePreview {
            // A tree of its own, with its own state and rebuild records —
            // the preview is not part of the host's tree and must not file
            // anything under the host's paths. The path prefix keeps any
            // shader slot it claims apart from the tree's.
            var context = BuildContext(
                environment: environment,
                effects: EffectQueue(),
                animations: AnimationStore(),
                records: RebuildRecords()
            )
            context.move(to: [-1])
            let node = buildNode(makePreview(), &context)
            let size = node.sizeThatFits(.unspecified)
            preview = .view(node, size: size, environment: environment)
        } else {
            // Place the node again, into a list nobody renders, under the
            // context it was last placed with — same rect, same transform,
            // same opacity — but unclipped, so a card half under the edge of
            // its scroll view is dragged whole.
            var context = source.value.context
            context.clip = nil
            context.clipCornerRadius = 0
            context.transformedClips = []
            // The snapshot wants the pixels of a drawing group inside, not a
            // node that would keep compositing at the view's old place.
            context.flattensRenderNodes = true
            context.freezesMotion = true
            var list = DisplayList()
            source.node.place(in: source.frame, proposal: source.value.proposal, context: context, into: &list)
            preview = .snapshot(list)
        }
    }

    // MARK: - The destination under the pointer

    /// Move to `point` and find the destination there. Tells a destination
    /// being left and one being entered, and answers whether that changed.
    @discardableResult
    func move(to point: Point, in root: ViewNode?) -> Bool {
        location = point
        let found = root?.hitTest(point, lookingFor: .dropTarget) { node -> DropTarget? in
            guard let target = node.content.dropTarget, target.accepts(payload) else { return nil }
            return target
        }
        guard found?.value.owner !== target?.value.owner else {
            target = found
            return false
        }
        target?.value.setTargeted(false)
        target = found
        found?.value.setTargeted(true)
        return true
    }

    /// Release at `point`: hand the payload to the destination there, if
    /// any. Whether it was taken.
    func drop(at point: Point, in root: ViewNode?) -> Bool {
        move(to: point, in: root)
        guard let target else { return false }
        let local = target.localPoint(for: point) ?? target.localPoint
        // Told "no longer over" before the drop lands, as SwiftUI does — so a
        // highlight is cleared before the action's own state change.
        target.value.setTargeted(false)
        let accepted = target.value.perform(payload, local)
        self.target = nil
        return accepted
    }

    // MARK: - The preview

    /// Paint the preview at the current location, over everything.
    func draw(into list: inout DisplayList) {
        var faded = DrawContext()
        faded.opacity = Self.previewOpacity
        faded.flattensRenderNodes = true
        faded.freezesMotion = true
        switch preview {
        case .snapshot(let snapshot):
            let moved = snapshot.translated(dx: location.x - origin.x, dy: location.y - origin.y)
            for index in moved.commands.indices {
                list.append(moved.commands[index].faded(under: faded), under: moved.state(at: index))
            }
        case .view(let node, let size, _):
            let rect = Rect(
                x: location.x - size.width / 2,
                y: location.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            node.place(in: rect, proposal: ProposedSize(size), context: faded, into: &list)
        }
    }
}

extension DrawCommand {

    /// The same command under `context`'s opacity. Its colors were resolved
    /// when it was first drawn, so the scheme in `context` changes nothing.
    func faded(under context: DrawContext) -> DrawCommand {
        guard context.opacity < 1 else { return self }
        switch self {
        case .shape(var draw):
            draw.fill = draw.fill.map(context.resolve)
            draw.stroke = draw.stroke.map(context.resolve)
            return .shape(draw)
        case .text(var draw):
            draw.color = context.resolve(draw.color)
            if let color = draw.underline?.color { draw.underline?.color = context.resolve(color) }
            if let color = draw.strikethrough?.color { draw.strikethrough?.color = context.resolve(color) }
            return .text(draw)
        case .image(var draw):
            draw.opacity *= context.opacity
            return .image(draw)
        case .svg(var draw):
            draw.opacity *= context.opacity
            return .svg(draw)
        case .canvas(var draw):
            draw.opacity *= context.opacity
            return .canvas(draw)
        }
    }
}
