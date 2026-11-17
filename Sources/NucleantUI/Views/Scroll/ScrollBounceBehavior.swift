//
//  ScrollBounceBehavior.swift
//  NucleantUI
//
//  `.scrollBounceBehavior`: whether a scroll view may be dragged past its
//  ends and bounce back, along each axis — always, or only when its content
//  is longer than the scroll view there. Through the environment, so it
//  reaches every scroll view below; `axes` says which of their axes it is
//  for.
//
//  A scroll view that neither bounces along an axis nor has anything to
//  scroll there does not move along it at all: a finger or a wheel moving
//  that way goes to a scroll view around it.
//

/// The ways that a scrollable view can bounce when it reaches the end of its
/// content.
///
/// Use the ``View/scrollBounceBehavior(_:axes:)`` view modifier to set a value
/// of this type for a scrollable view, like a ``ScrollView`` or a ``List``.
/// The value configures the bounce behavior when people scroll to the end of
/// the view's content.
///
/// You can configure each scrollable axis to use a different bounce mode.
public struct ScrollBounceBehavior: Sendable {
    enum Kind: Sendable {
        case automatic, always, basedOnSize
    }

    let kind: Kind

    /// The automatic behavior.
    ///
    /// The scrollable view automatically chooses whether content bounces when
    /// people scroll to the end of the view's content. By default, scrollable
    /// views use the ``ScrollBounceBehavior/always`` behavior.
    public static var automatic: ScrollBounceBehavior { ScrollBounceBehavior(kind: .automatic) }

    /// The scrollable view always bounces.
    ///
    /// The scrollable view always bounces along the specified axis,
    /// regardless of the size of the content.
    public static var always: ScrollBounceBehavior { ScrollBounceBehavior(kind: .always) }

    /// The scrollable view bounces when its content is large enough to require
    /// scrolling.
    ///
    /// The scrollable view bounces along the specified axis if the size of
    /// the content exceeds the size of the scrollable view in that axis.
    public static var basedOnSize: ScrollBounceBehavior { ScrollBounceBehavior(kind: .basedOnSize) }

    /// Whether a scroll view under this behavior bounces along an axis its
    /// content is, or is not, longer than it along.
    func bounces(contentIsLonger: Bool) -> Bool {
        switch kind {
        case .automatic, .always: true
        case .basedOnSize: contentIsLonger
        }
    }
}

private struct VerticalScrollBounceBehaviorKey: EnvironmentKey {
    static var defaultValue: ScrollBounceBehavior { .automatic }
}

private struct HorizontalScrollBounceBehaviorKey: EnvironmentKey {
    static var defaultValue: ScrollBounceBehavior { .automatic }
}

extension EnvironmentValues {
    /// The scroll bounce mode for the vertical axis of scrollable views.
    ///
    /// Use the ``View/scrollBounceBehavior(_:axes:)`` view modifier to set this
    /// value in the ``Environment``.
    public var verticalScrollBounceBehavior: ScrollBounceBehavior {
        get { self[VerticalScrollBounceBehaviorKey.self] }
        set { self[VerticalScrollBounceBehaviorKey.self] = newValue }
    }

    /// The scroll bounce mode for the horizontal axis of scrollable views.
    ///
    /// Use the ``View/scrollBounceBehavior(_:axes:)`` view modifier to set this
    /// value in the ``Environment``.
    public var horizontalScrollBounceBehavior: ScrollBounceBehavior {
        get { self[HorizontalScrollBounceBehaviorKey.self] }
        set { self[HorizontalScrollBounceBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Configures the bounce behavior of scrollable views along the specified
    /// axis.
    ///
    /// Use this modifier to indicate whether scrollable views bounce when
    /// people scroll to the end of the view's content, taking into account the
    /// relative sizes of the view and its content. For example, the following
    /// ``ScrollView`` only enables bounce behavior if its content is large
    /// enough to require scrolling:
    ///
    /// ```swift
    /// ScrollView {
    ///     Text("Small")
    ///     Text("Content")
    /// }
    /// .scrollBounceBehavior(.basedOnSize)
    /// ```
    ///
    /// The modifier passes the scroll bounce mode through the ``Environment``,
    /// which means that the mode affects any scrollable views in the modified
    /// view hierarchy. Provide an axis to the modifier to constrain the kinds
    /// of scrollable views that the mode affects. For example, all the scroll
    /// views in the following example can access the mode value, but
    /// only the two nested scroll views are affected, because only they use
    /// horizontal scrolling:
    ///
    /// ```swift
    /// ScrollView { // Defaults to vertical scrolling.
    ///     ScrollView(.horizontal) {
    ///         ShelfContent()
    ///     }
    ///     ScrollView(.horizontal) {
    ///         ShelfContent()
    ///     }
    /// }
    /// .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    /// ```
    ///
    /// A scroll view that does not bounce along an axis its content fits
    /// along does not move along it: a drag that way goes to a scroll view
    /// around it.
    ///
    /// - Parameters:
    ///   - behavior: The bounce behavior to apply to any scrollable views
    ///     within the configured view. Use one of the ``ScrollBounceBehavior``
    ///     values.
    ///   - axes: The set of axes to apply `behavior` to. The default is
    ///     ``Axis/vertical``.
    /// - Returns: A view that's configured with the specified scroll bounce
    ///   behavior.
    public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
        _ModifierView(content: self, modifier: ScrollBounceBehaviorModifier(behavior: behavior, axes: axes))
    }
}

struct ScrollBounceBehaviorModifier: PrimitiveModifier {
    let behavior: ScrollBounceBehavior
    let axes: Axis.Set

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        if axes.contains(.vertical) { environment.verticalScrollBounceBehavior = behavior }
        if axes.contains(.horizontal) { environment.horizontalScrollBounceBehavior = behavior }
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }

    func _isEquivalent(to other: ScrollBounceBehaviorModifier) -> Bool {
        behavior.kind == other.behavior.kind && axes == other.axes
    }
}
