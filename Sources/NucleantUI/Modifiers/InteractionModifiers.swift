//
//  InteractionModifiers.swift
//  NucleantUI
//

extension View {

    /// Attach a raw hit target. Used by `Button`; exposed with an underscore
    /// because the supported spelling is `.onTapGesture`.
    public func _hitTarget(_ target: HitTarget) -> some View {
        _ModifierView(content: self, modifier: HitTargetModifier(target: target))
    }

    /// Runs `action` when this view is tapped.
    public func onTapGesture(perform action: @escaping @MainActor () -> Void) -> some View {
        _ModifierView(content: self, modifier: TapModifier(action: action))
    }

    /// Runs `action` when this view is tapped, with the tap location in the
    /// view's own coordinate space.
    public func onTapGesture(
        perform action: @escaping @MainActor (Point) -> Void
    ) -> some View {
        _ModifierView(content: self, modifier: LocatedTapModifier(action: action))
    }

    /// Runs `action` the first time this view appears — once per appearance,
    /// not once per rebuild (identity is structural, the same key `@State`
    /// uses).
    public func onAppear(perform action: @escaping @MainActor () -> Void) -> some View {
        _ModifierView(content: self, modifier: OnAppearModifier(action: action))
    }
}

extension View {

    /// Runs `action` when this view leaves the tree — removed by an `if`, a
    /// `ForEach` or anything else that stops building it. Once per
    /// appearance, like `onAppear`, and with the action from the most
    /// recent build, so it sees the values that build captured.
    public func onDisappear(perform action: (@MainActor () -> Void)? = nil) -> some View {
        _ModifierView(content: self, modifier: OnDisappearModifier(action: action))
    }
}


// MARK: - The modifiers
//
// Each holds an action, which says nothing comparable about itself, so
// each is built again whenever its parent is — with the latest action.

/// `._hitTarget(_:)`.
struct HitTargetModifier: PrimitiveModifier {
    let target: HitTarget

    func makeContent(_ context: inout BuildContext) -> InteractionContent {
        InteractionContent(target: target)
    }

    func _isEquivalent(to other: HitTargetModifier) -> Bool { false }
}

/// `.onTapGesture(perform:)`.
struct TapModifier: PrimitiveModifier {
    let action: @MainActor () -> Void

    func makeContent(_ context: inout BuildContext) -> InteractionContent {
        let action = self.action
        return InteractionContent(target: HitTarget(
            isEnabled: context.environment.isEnabled,
            onRelease: { _, inside in if inside { action() } }
        ))
    }

    func _isEquivalent(to other: TapModifier) -> Bool { false }
}

/// `.onTapGesture(perform:)` with the location.
struct LocatedTapModifier: PrimitiveModifier {
    let action: @MainActor (Point) -> Void

    func makeContent(_ context: inout BuildContext) -> InteractionContent {
        let action = self.action
        return InteractionContent(target: HitTarget(
            isEnabled: context.environment.isEnabled,
            onRelease: { point, inside in if inside { action(point) } }
        ))
    }

    func _isEquivalent(to other: LocatedTapModifier) -> Bool { false }
}

/// `.onAppear(perform:)`.
struct OnAppearModifier: PrimitiveModifier {
    let action: @MainActor () -> Void

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        context.effects.onAppear(at: context.position, action)
        return environmentContent(context)
    }

    func _isEquivalent(to other: OnAppearModifier) -> Bool { false }
}

/// `.onDisappear(perform:)`.
struct OnDisappearModifier: PrimitiveModifier {
    let action: (@MainActor () -> Void)?

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        if let action {
            context.effects.onDisappear(at: context.position, action)
        }
        return environmentContent(context)
    }

    func _isEquivalent(to other: OnDisappearModifier) -> Bool { false }
}
