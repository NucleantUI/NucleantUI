//
//  PlaceholderContentView.swift
//  NucleantUI
//
//  The `content` a transition's body is handed. It is not the view the
//  transition is applied to, only a stand-in for it — the body is written
//  once for every view it could be put on — and building the stand-in
//  builds what it stands for: a view handed to `apply(content:phase:)`,
//  built where the placeholder stands, or the child a container already
//  built at its own place, handed back as it is.
//

/// A placeholder used to construct an inline modifier, transition, or other
/// helper type.
///
/// You don't use this type directly. Instead NucleantUI creates this type on
/// your behalf: it is the `content` of ``Transition/body(content:phase:)``,
/// and builds as the view the transition is applied to.
@View
public struct PlaceholderContentView<Value> {

    /// What the placeholder builds as.
    let source: PlaceholderContent

    init(source: PlaceholderContent, _viewID: ViewID = #viewID) {
        self.source = source
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }

    /// Two placeholders build the same thing when what they stand for is
    /// the same: the same standing node, or equivalent views.
    public func _isEquivalent(to other: PlaceholderContentView<Value>) -> Bool {
        source.isEquivalent(to: other.source)
    }
}

extension PlaceholderContentView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        source.makeNode(&context)
    }
}

// MARK: - What a placeholder stands for

/// What a `PlaceholderContentView` builds as. Each kind is a subclass; the
/// placeholder holds this base, so a transition's body type never depends
/// on the type of the view it is put on.
@MainActor
class PlaceholderContent {

    func makeNode(_ context: inout BuildContext) -> ViewNode {
        fatalError("PlaceholderContent is abstract")
    }

    func isEquivalent(to other: PlaceholderContent) -> Bool {
        fatalError("PlaceholderContent is abstract")
    }
}

/// A view handed to `apply(content:phase:)`, built where the placeholder
/// stands — in slot `[0]` under it, so the two are never one path.
@MainActor
final class PlaceholderViewContent<Content: View>: PlaceholderContent {
    let view: Content

    init(_ view: Content) {
        self.view = view
    }

    override func makeNode(_ context: inout BuildContext) -> ViewNode {
        context.child(0) { ctx in buildNode(view, &ctx) }
    }

    override func isEquivalent(to other: PlaceholderContent) -> Bool {
        guard let other = other as? PlaceholderViewContent<Content> else { return false }
        return _areEquivalent(view, other.view)
    }
}

/// A node already built elsewhere — the one a container puts between a
/// transition's body and its child (TransitionSlots.swift) — handed back
/// as it stands. Nothing is built here: the child keeps its own path.
@MainActor
final class PlaceholderNodeContent: PlaceholderContent {
    let node: ViewNode

    init(_ node: ViewNode) {
        self.node = node
    }

    override func makeNode(_ context: inout BuildContext) -> ViewNode {
        node
    }

    override func isEquivalent(to other: PlaceholderContent) -> Bool {
        (other as? PlaceholderNodeContent)?.node === node
    }
}

// MARK: - A transition applied to a view

/// What `Transition.apply(content:phase:)` returns: `transition`'s body in
/// `phase`, with `content` built where the body's placeholder stands.
@View
struct AppliedTransition<T: Transition, Content: View> {
    let transition: T
    let phase: TransitionPhase
    let content: Content

    var body: some View {
        transition.body(
            content: PlaceholderContentView<T>(source: PlaceholderViewContent(content)),
            phase: phase
        )
    }
}
