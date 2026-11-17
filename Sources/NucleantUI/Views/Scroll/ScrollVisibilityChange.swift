//
//  ScrollVisibilityChange.swift
//  NucleantUI
//
//  `.onScrollVisibilityChange`: a view told whether it is in view in the
//  scroll view around it — as much of it as the threshold says. Worked out
//  each time the view is placed, so a scroll that moves it is seen; the
//  answer last handed on is kept on the view's position.
//

extension View {
    /// Adds an action to be called when the view crosses the threshold to be
    /// considered on/off screen.
    ///
    /// Use this modifier to be informed when the view has crossed the
    /// provided threshold to be considered on/off screen.
    ///
    ///     struct VideoPlayer: View {
    ///         @State var playing: Bool
    ///
    ///         var body: some View {
    ///             Group {
    ///                 // ...
    ///             }
    ///             .onScrollVisibilityChange(threshold: 0.2) { isVisible in
    ///                 playing = isVisible
    ///             }
    ///         }
    ///     }
    ///
    /// When the view appears on-screen, the action will be called if the threshold
    /// has already been reached.
    ///
    /// Outside any scroll view, a view is in view.
    ///
    /// - Parameters:
    ///   - threshold: The amount required to be visible within the viewport of the parent
    ///   view before the `action` is fired. By default when the view has crossed more than 50%
    ///   on-screen, the action will be called.
    ///   - action: The action which will be called when the threshold has been reached.
    public func onScrollVisibilityChange(
        threshold: Double = 0.5,
        _ action: @escaping @MainActor (Bool) -> Void
    ) -> some View {
        _ModifierView(content: self, modifier: ScrollVisibilityChangeModifier(threshold: threshold, action: action))
    }
}

struct ScrollVisibilityChangeModifier: PrimitiveModifier {
    let threshold: Double
    let action: @MainActor (Bool) -> Void

    func makeContent(_ context: inout BuildContext) -> ScrollVisibilityChangeContent {
        ScrollVisibilityChangeContent(placed: context.position.placed, effects: context.effects, threshold: threshold, action: action)
    }

    /// Built again whenever its parent is, for the latest closure.
    func _isEquivalent(to other: ScrollVisibilityChangeModifier) -> Bool { false }
}

struct ScrollVisibilityChangeContent: NodeContent {
    /// Whether it was in view last time, kept on its view's position.
    let placed: PlacedValue
    let effects: EffectQueue
    let threshold: Double
    let action: @MainActor (Bool) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        if !context.freezesMotion {
            let isVisible = isInView(rect, context: context)
            if let wasVisible = placed.value?.value(as: Bool.self) {
                if wasVisible != isVisible {
                    placed.value = Box(isVisible)
                    effects.afterPass { [action] in action(isVisible) }
                }
            } else {
                // The first time: told only if it is in view.
                placed.value = Box(isVisible)
                if isVisible {
                    effects.afterPass { [action] in action(true) }
                }
            }
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
    }

    /// Whether at least `threshold` of the view placed at `rect` is in the
    /// innermost scroll view's viewport.
    private func isInView(_ rect: Rect, context: DrawContext) -> Bool {
        let proxy = GeometryProxy(
            geometry: PlacedGeometry(rect: rect, transform: context.transform, spaces: context.coordinateSpaces),
            log: nil
        )
        guard let scroll = proxy.bounds(of: .scrollView) else { return true }
        let frame = proxy.frame(in: .scrollView)
        let fraction = frame.visibleFraction(in: Rect(origin: .zero, size: scroll.size))
        return fraction > 0 && fraction >= threshold
    }
}
