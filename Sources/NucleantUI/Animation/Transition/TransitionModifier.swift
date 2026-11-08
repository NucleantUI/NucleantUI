//
//  TransitionModifier.swift
//  NucleantUI
//
//  `.transition(_:)`: the transition a view has, carried up from where it
//  is written — through the modifiers around it and the body of the view
//  it is in — to the container that inserts or removes that view, as the
//  node's `transitionTrait`. Nothing is applied here; the container builds
//  the transition's body around the whole view (TransitionSlots.swift).
//

extension View {

    /// Associates a transition with the view.
    ///
    /// When this view appears or disappears, the transition will be applied
    /// to it, allowing for animating it in and out.
    ///
    /// The following code will conditionally show MyView, and when it
    /// appears or disappears, will use a slide transition to show it.
    ///
    ///     if isActive {
    ///         MyView()
    ///             .transition(.slide)
    ///     }
    ///     Button("Toggle") {
    ///         withAnimation {
    ///             isActive.toggle()
    ///         }
    ///     }
    @_disfavoredOverload
    public func transition(_ t: AnyTransition) -> some View {
        TransitionTraitView(content: self, transition: t, _viewID: _viewID)
    }

    /// Associates a transition with the view.
    ///
    /// When this view appears or disappears, the transition will be applied
    /// to it, allowing for animating it in and out.
    ///
    /// The following code will conditionally show MyView, and when it
    /// appears or disappears, will use a custom RotatingFadeTransition
    /// transition to show it.
    ///
    ///     if isActive {
    ///         MyView()
    ///             .transition(RotatingFadeTransition())
    ///     }
    ///     Button("Toggle") {
    ///         withAnimation {
    ///             isActive.toggle()
    ///         }
    ///     }
    public func transition<T: Transition>(_ transition: T) -> some View {
        TypedTransitionTraitView(content: self, transition: transition, _viewID: _viewID)
    }
}

/// `.transition(_ t: AnyTransition)`'s view: `content`, with `transition`
/// on its node for the container above to read. The call site is the
/// content's — the transition does not make it a different view.
@View
struct TransitionTraitView<Content: View> {
    let content: Content
    let transition: AnyTransition

    var body: Never { bodyUnavailable() }
}

extension TransitionTraitView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let child = context.child(0) { ctx in buildNode(content, &ctx) }
        let node = ViewNode(content: TransitionTraitContent(), children: [child])
        // The outermost `.transition` of a view is the one it has.
        node.transitionTrait = transition
        node.gridCellTraits = child.gridCellTraits
        node.layoutValues = child.layoutValues
        return node
    }
}

/// `.transition<T: Transition>(_:)`'s view: the same, holding the
/// transition as the type it was written as — compared as that type — and
/// erasing it only for the node.
@View
struct TypedTransitionTraitView<Content: View, T: Transition> {
    let content: Content
    let transition: T

    var body: Never { bodyUnavailable() }

    /// Equivalent content, and a transition that builds the same body —
    /// one of a type that stores nothing always does.
    func _isEquivalent(to other: TypedTransitionTraitView<Content, T>) -> Bool {
        transitionsAreEquivalent(transition, other.transition) && _areEquivalent(content, other.content)
    }
}

extension TypedTransitionTraitView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let child = context.child(0) { ctx in buildNode(content, &ctx) }
        let node = ViewNode(content: TransitionTraitContent(), children: [child])
        node.transitionTrait = AnyTransition(transition)
        node.gridCellTraits = child.gridCellTraits
        node.layoutValues = child.layoutValues
        return node
    }
}

/// The node `.transition` makes: laid out, drawn and hit exactly as what
/// it wraps — it is only there to carry the transition.
struct TransitionTraitContent: NodeContent {}
