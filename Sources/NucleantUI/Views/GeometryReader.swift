//
//  GeometryReader.swift
//  NucleantUI
//
//  A view whose content is a function of its own size and place, which
//  only layout knows. So the content is built during placement: the reader
//  is offered its rect, hands the content a proxy for it, builds what comes
//  back where the content stands, and places that — all in the same pass,
//  so the first frame already shows content built for the size it has.
//
//  The build is an ordinary one, through the records of the tree the reader
//  is in: what stood inside is reused when equivalent and keeps its
//  `@State`, and what is gone is released. When the reader itself is built
//  again (its parent re-ran), it builds its content right there, with
//  where it was last placed, so the build pass keeps what stands inside as
//  it keeps everything else; placement then builds it once more only if an
//  answer the content read has changed (see `GeometryReadLog`).
//

/// A container view that defines its content as a function of its own size and
/// coordinate space.
///
/// This view returns a flexible preferred size to its parent layout: it
/// takes all it is offered. Its content is offered the same, and placed at
/// its top-leading corner.
///
/// ```swift
/// GeometryReader { proxy in
///     if proxy.size.width > 600 {
///         HStack { sidebar; detail }
///     } else {
///         VStack { picker; detail }
///     }
/// }
/// ```
@View
public struct GeometryReader<Content: View> {

    public var content: (GeometryProxy) -> Content

    @State private var log = GeometryReadLog()

    public init(_viewID: ViewID = #viewID, @ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }

    /// The closure is the content: two readers are never known to build the
    /// same thing.
    public func _isEquivalent(to other: GeometryReader<Content>) -> Bool { false }
}

extension GeometryReader: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        var inner = context
        // The content is not in a stack of its own; clear any inherited axis
        // so a `Spacer` inside doesn't stretch along the enclosing stack's.
        inner.stackAxis = nil
        let reader = GeometryReaderContent(content: content, log: log, context: inner)
        // Placed before: built now, with where it was, so what stands
        // inside is kept or released by this pass like everything else.
        // Never placed: there is nothing to build it for yet, and nothing
        // standing inside to keep — placement builds it.
        let child = log.current.map { reader.build(at: $0, context: inner) }
            ?? ViewNode(content: GroupContent())
        return ViewNode(content: reader, children: [child])
    }
}

struct GeometryReaderContent<Content: View>: NodeContent {
    let content: (GeometryProxy) -> Content
    let log: GeometryReadLog

    /// The build the reader was made in: the records, state store and
    /// environment its content is built with during placement.
    let context: BuildContext

    /// Takes everything it is offered, on both axes.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        .flexible
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context draw: DrawContext, into list: inout DisplayList) {
        // A reader drawn where it stood — on its way out, or in a drag's
        // snapshot — shows what it holds as it is.
        if !draw.freezesMotion {
            let placed = PlacedGeometry(rect: rect, transform: draw.transform, spaces: draw.coordinateSpaces)
            let isStale = log.builtWith.map { log.answersDiffer(between: $0, and: placed) } ?? true
            log.current = placed
            if isStale {
                rebuild(node, at: placed)
            }
        }
        let offered = ProposedSize(rect.size)
        for child in node.layoutChildren {
            child.place(
                in: Rect(origin: rect.origin, size: child.sizeThatFits(offered)),
                proposal: offered,
                context: draw,
                into: &list
            )
        }
    }

    /// The content for `placed`, built at the reader's child slot. Its
    /// `@State` and `@Observable` reads are the reader's, as a body's are
    /// its view's — whoever runs this has the reader's path published.
    func build(at placed: PlacedGeometry, context: BuildContext) -> ViewNode {
        log.builtWith = placed
        let path = context.path
        let proxy = GeometryProxy(geometry: placed, log: log)
        let view = trackingObservation(at: path) { content(proxy) }
        return context.child(0) { ctx in buildNode(view, &ctx) }
    }

    /// Build the content again during placement, in place of what stands.
    private func rebuild(_ node: ViewNode, at placed: PlacedGeometry) {
        var context = self.context
        let path = context.path
        // Whatever this frame serves, not the frame the reader was built in.
        context.transaction = context.animations.transaction
        context.records.beginRebuild(under: path + [0])

        DependencyTracker.shared.push(path)
        let child = build(at: placed, context: context)
        DependencyTracker.shared.pop()
        context.records.addReads(DependencyTracker.shared.takeReads(for: path), at: path)
        releaseDeparted(context)

        node.replaceChild(at: 0, with: child)
        // The reader's size never depends on its content, so what was
        // measured above stands; what was reduced from preferences below
        // it does not.
        var ancestor: ViewNode? = node
        while let current = ancestor {
            current.preferenceCache.removeAll(keepingCapacity: true)
            ancestor = current.parent
        }
        context.effects.noteBuiltDuringLayout()
    }

    /// Let go of what the build did not put back — the same bookkeeping the
    /// host does after a rebuild, for the views that were inside the reader
    /// and are not any more.
    private func releaseDeparted(_ context: BuildContext) {
        let departed = context.records.endRebuild()
        guard !departed.isEmpty else { return }
        for (path, entry) in departed {
            for storage in entry.reads {
                storage.readers.removeValue(forKey: path)
            }
            context.store.release(entry.stateKeys)
        }
        let paths = Set(departed.map { $0.0 })
        context.effects.forget(paths: paths)
        context.animations.forget(paths: paths)
    }
}
