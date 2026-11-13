//
//  HoverModifiers.swift
//  NucleantUI
//

extension View {
    /// Runs `action` with `true` when the pointer moves over this view and
    /// `false` when it leaves — a mouse only; a finger never hovers.
    ///
    /// ```swift
    /// row.onHover { hovering in isHighlighted = hovering }
    /// ```
    public func onHover(perform action: @escaping @MainActor (Bool) -> Void) -> some View {
        _ModifierView(content: self, modifier: HoverModifier(action: action))
    }
}

/// A node that wants to know when the pointer is over it.
@MainActor
final class HoverTarget {
    /// The node's structural path — its identity across rebuilds, the same
    /// way `DropTarget` is known: the `true` this target is told usually
    /// writes state, which rebuilds the view and replaces this object, and
    /// the next move must still see the same target.
    let path: [Int]
    let isEnabled: Bool
    let action: @MainActor (Bool) -> Void

    init(path: [Int], isEnabled: Bool, action: @escaping @MainActor (Bool) -> Void) {
        self.path = path
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// `.onHover(perform:)`.
struct HoverContent: NodeContent {
    let target: HoverTarget

    var hoverTarget: HoverTarget? { target.isEnabled ? target : nil }
}

/// `.onHover(perform:)`. Built again whenever its parent is, for the
/// latest action.
struct HoverModifier: PrimitiveModifier {
    let action: @MainActor (Bool) -> Void

    func makeContent(_ context: inout BuildContext) -> HoverContent {
        HoverContent(target: HoverTarget(
            path: context.path,
            isEnabled: context.environment.isEnabled,
            action: action
        ))
    }

    func _isEquivalent(to other: HoverModifier) -> Bool { false }
}
