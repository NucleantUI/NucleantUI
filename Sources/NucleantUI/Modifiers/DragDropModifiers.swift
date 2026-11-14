//
//  DragDropModifiers.swift
//  NucleantUI
//
//  `.draggable(_:)` and `.dropDestination(for:action:isTargeted:)`. The
//  modifiers mark nodes; the drag itself — the preview following the pointer,
//  the destination under it, the hand-over on release — is run by `ViewHost`
//  (see `DragSession`).
//

extension View {

    /// Lets this view be dragged, carrying `payload`. The view itself is the
    /// preview that follows the pointer — a snapshot of it as it was drawn.
    ///
    /// ```swift
    /// TrackCard(track)
    ///     .draggable(track)
    /// ```
    ///
    /// The payload closure runs when the drag begins, not when the view is
    /// built. A drag starts once the pointer has moved a few points with the
    /// button held; a plain click still reaches whatever is inside. On a
    /// touch host with a scroll view around this view, a drag starts from a
    /// press held still instead, so a finger can still scroll the list.
    public func draggable<T: Transferable>(
        _ payload: @autoclosure @escaping () -> T
    ) -> some View {
        _ModifierView(content: self, modifier: DraggableModifier(makePayload: { TransferPayload(payload()) }, makePreview: nil))
    }

    /// As above, with a view of your own as the preview, centred on the
    /// pointer.
    public func draggable<T: Transferable, Preview: View>(
        _ payload: @autoclosure @escaping () -> T,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        _ModifierView(content: self, modifier: DraggableModifier(
            makePayload: { TransferPayload(payload()) },
            makePreview: { AnyView(preview()) }
        ))
    }

    /// Lets a drag carrying a `T` end on this view.
    ///
    /// ```swift
    /// bin.dropDestination(for: Track.self) { tracks, location in
    ///     bus.append(contentsOf: tracks)
    ///     return true
    /// } isTargeted: { over in isHighlighted = over }
    /// ```
    ///
    /// `action` gets the dropped items and the drop point in this view's
    /// own coordinates, and answers whether it took them. `isTargeted` is
    /// told when a drag this view could take enters and leaves it — and
    /// `false` again on the drop. A drag whose payload cannot become a `T`
    /// passes over this view as if it weren't there.
    public func dropDestination<T: Transferable>(
        for payloadType: T.Type = T.self,
        action: @escaping @MainActor ([T], Point) -> Bool,
        isTargeted: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> some View {
        _ModifierView(content: self, modifier: DropDestinationModifier<T>(action: action, isTargeted: isTargeted))
    }
}

/// A node a drag can start on.
@MainActor
final class DragSource {
    let isEnabled: Bool

    /// Where the source's view stands. A custom preview is built under the
    /// environment filed there when the drag begins — the one the view
    /// stands under then, which a parent that re-ran without rebuilding it
    /// may have moved on from the one it was built with.
    let owner: PositionHandle

    let makePayload: @MainActor () -> TransferPayload
    let makePreview: (@MainActor () -> AnyView)?

    /// How far the pointer travels before a press on this node is a drag —
    /// enough that a click with a shaky hand is still a click.
    let minimumDistance = 4.0

    /// The proposal and draw context the node was last placed under, kept so
    /// the drag can place it again into a list of its own for the preview.
    var proposal: ProposedSize = .unspecified
    var context = DrawContext()

    init(
        isEnabled: Bool,
        owner: PositionHandle,
        makePayload: @escaping @MainActor () -> TransferPayload,
        makePreview: (@MainActor () -> AnyView)?
    ) {
        self.isEnabled = isEnabled
        self.owner = owner
        self.makePayload = makePayload
        self.makePreview = makePreview
    }
}

/// A node a drag can end on.
@MainActor
final class DropTarget {
    /// The view it belongs to, by its position — its identity across
    /// rebuilds. An `isTargeted` write rebuilds the view and with it this
    /// object, and a session comparing objects would see a new target every
    /// frame and tell it "entered" again; comparing owners sees the same
    /// one.
    let owner: PositionHandle
    let isEnabled: Bool
    let accepts: @MainActor (TransferPayload) -> Bool
    let perform: @MainActor (TransferPayload, Point) -> Bool
    let setTargeted: @MainActor (Bool) -> Void

    init(
        owner: PositionHandle,
        isEnabled: Bool,
        accepts: @escaping @MainActor (TransferPayload) -> Bool,
        perform: @escaping @MainActor (TransferPayload, Point) -> Bool,
        setTargeted: @escaping @MainActor (Bool) -> Void
    ) {
        self.owner = owner
        self.isEnabled = isEnabled
        self.accepts = accepts
        self.perform = perform
        self.setTargeted = setTargeted
    }
}

/// `.draggable(_:)`.
struct DragSourceContent: NodeContent {
    let source: DragSource

    var dragSource: DragSource? { source.isEnabled ? source : nil }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        source.proposal = proposal
        source.context = context
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }
}

/// `.dropDestination(for:action:isTargeted:)`.
struct DropTargetContent: NodeContent {
    let target: DropTarget

    var dropTarget: DropTarget? { target.isEnabled ? target : nil }
}

/// `.draggable(_:)` and `.draggable(_:preview:)`. Built again whenever its
/// parent is, for the latest closures.
struct DraggableModifier: PrimitiveModifier {
    let makePayload: @MainActor () -> TransferPayload
    let makePreview: (@MainActor () -> AnyView)?

    func makeContent(_ context: inout BuildContext) -> DragSourceContent {
        DragSourceContent(source: DragSource(
            isEnabled: context.environment.isEnabled,
            owner: context.position.handle,
            makePayload: makePayload,
            makePreview: makePreview
        ))
    }

    func _isEquivalent(to other: DraggableModifier) -> Bool { false }
}

/// `.dropDestination(for:action:isTargeted:)`. Built again whenever its
/// parent is, for the latest closures.
struct DropDestinationModifier<T: Transferable>: PrimitiveModifier {
    let action: @MainActor ([T], Point) -> Bool
    let isTargeted: @MainActor (Bool) -> Void

    func makeContent(_ context: inout BuildContext) -> DropTargetContent {
        let action = self.action
        return DropTargetContent(target: DropTarget(
            owner: context.position.handle,
            isEnabled: context.environment.isEnabled,
            accepts: { payload in payload.canImport(T.self) },
            perform: { payload, location in
                do {
                    guard let item = try payload.load(T.self) else { return false }
                    return action([item], location)
                } catch {
                    InputTrace.log("drop of \(payload.itemName) as \(T.self) failed: \(error)")
                    return false
                }
            },
            setTargeted: isTargeted
        ))
    }

    func _isEquivalent(to other: DropDestinationModifier<T>) -> Bool { false }
}
