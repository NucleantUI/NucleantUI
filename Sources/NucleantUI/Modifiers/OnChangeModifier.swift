//
//  OnChangeModifier.swift
//  NucleantUI
//
//  `.onChange`: an action run when a value changes from one build of a view
//  to the next, kept by the pass's effects under the view's structural
//  identity — the same key `onAppear` uses — and run once the tree is
//  built, as `onAppear` is.
//

extension View {

    /// Runs `action` when `value` changes from one build of this view to
    /// the next — handed the value it was and the value it is now.
    ///
    /// The action is the latest build's, so whatever else it captured is as
    /// new as `newValue`. With `initial`, it also runs when the view
    /// appears, with the value it appeared with as both.
    ///
    /// ```swift
    /// .onChange(of: playState) { oldState, newState in
    ///     model.playStateDidChange(from: oldState, to: newState)
    /// }
    /// ```
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping @MainActor (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        _ModifierView(content: self) { context in
            context.effects.onChange(
                StateKey(path: context.path, propertyIndex: -1, viewType: ObjectIdentifier(OnChangeMarker.self)),
                of: value,
                initial: initial,
                action
            )
            return EnvironmentContent(colorScheme: context.environment.colorScheme)
        }
    }

    /// Runs `action` when `value` changes from one build of this view to
    /// the next — and, with `initial`, when the view appears.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping @MainActor () -> Void
    ) -> some View {
        onChange(of: value, initial: initial) { _, _ in action() }
    }
}

/// Stands in for a view type in the key, as `OnAppearMarker` does.
private enum OnChangeMarker {}
