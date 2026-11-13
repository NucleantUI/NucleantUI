//
//  AnimationModifiers.swift
//  NucleantUI
//
//  `.animation` and `.transaction`: changing, for one subtree, how the
//  change being built animates. Each acts twice — on the transaction the
//  subtree is *built* under (which starts value animations and
//  transitions), and on the animation it is *placed* under in the same
//  frame (which starts geometry animations).
//

extension View {

    /// Animates this view with `animation` whenever `value` changes —
    /// whatever changed it, `withAnimation` or not. `nil` makes such a
    /// change happen at once.
    ///
    /// ```swift
    /// Circle()
    ///     .scaleEffect(isOn ? 1.5 : 1)
    ///     .animation(.bouncy, value: isOn)
    /// ```
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        _ModifierView(content: self, modifier: AnimationValueModifier(animation: animation, value: value))
    }

    /// Animates every change to this view with `animation`.
    @available(*, deprecated, message: "Use withAnimation or animation(_:value:) instead.")
    public func animation(_ animation: Animation?) -> some View {
        _ModifierView(content: self, modifier: AnimationModifier(animation: animation))
    }

    /// Adjusts the transaction of any change that reaches this view —
    /// `$0.animation = nil` to have this view jump while the rest animates.
    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        _ModifierView(content: self, modifier: TransactionModifier(transform: transform))
    }
}

/// `.animation(_:value:)`. Built again whenever its parent is — the value
/// it last saw is filed by path, and each build asks whether it changed.
struct AnimationValueModifier<V: Equatable>: PrimitiveModifier {
    let animation: Animation?
    let value: V

    func makeContent(_ context: inout BuildContext) -> AnimationScopeContent {
        let changed = context.animations.valueChanged(value, at: context.path)
        // `disablesAnimations` is the change asking to be animated only
        // by its own transaction.
        let overrides = changed && !context.transaction.disablesAnimations
        let animation = self.animation
        if overrides {
            context.transaction.animation = animation
        }
        return AnimationScopeContent(
            frame: context.animations.frame,
            adjust: overrides ? { $0 = animation } : nil
        )
    }

    func _isEquivalent(to other: AnimationValueModifier<V>) -> Bool { false }
}

/// `.animation(_:)`, value-free: applies to every change that is built.
struct AnimationModifier: PrimitiveModifier {
    let animation: Animation?

    func makeContent(_ context: inout BuildContext) -> AnimationScopeContent {
        let overrides = !context.transaction.disablesAnimations
        let animation = self.animation
        if overrides {
            context.transaction.animation = animation
        }
        return AnimationScopeContent(
            frame: context.animations.frame,
            adjust: overrides ? { $0 = animation } : nil,
            appliesToEveryBuild: true
        )
    }

    func _isEquivalent(to other: AnimationModifier) -> Bool { false }
}

/// `.transaction(_:)`.
struct TransactionModifier: PrimitiveModifier {
    let transform: (inout Transaction) -> Void

    func makeContent(_ context: inout BuildContext) -> AnimationScopeContent {
        transform(&context.transaction)
        let transform = self.transform
        return AnimationScopeContent(
            frame: context.animations.frame,
            adjust: { animation in
                var transaction = Transaction(animation: animation)
                transform(&transaction)
                animation = transaction.animation
            },
            appliesToEveryBuild: true
        )
    }

    func _isEquivalent(to other: TransactionModifier) -> Bool { false }
}

/// Places its child under an adjusted animation in the frame the change
/// was built in. Lays out as its child does.
struct AnimationScopeContent: NodeContent {
    /// The frame this node was built in.
    let frame: Int
    /// What happens to the animation the subtree is placed under.
    let adjust: ((inout Animation?) -> Void)?
    /// Whether the adjustment holds for any frame that builds something,
    /// not only the one that built this node — the value-free `.animation`
    /// and `.transaction`, which apply to every change.
    var appliesToEveryBuild = false

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        if let adjust, let store = AnimationStore.current, store.isCommitPass,
           appliesToEveryBuild || store.frame == frame {
            adjust(&inner.animation)
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}
