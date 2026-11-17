//
//  DefaultScrollAnchor.swift
//  NucleantUI
//
//  `.defaultScrollAnchor`: the point of its content a scroll view keeps to —
//  where it starts, how it moves as its content or its own size changes,
//  and where it puts content smaller than itself. A scroll view takes the
//  anchors for itself: the views inside it do not inherit them.
//

/// A type defining the role of a scroll anchor.
///
/// You can associate a ``UnitPoint`` to a ``ScrollView`` using the
/// ``View/defaultScrollAnchor(_:)`` modifier. By default, the system
/// uses this point for different kinds of behaviors including:
///   - Where the scroll view should initially be scrolled
///   - How the scroll view should handle content size or
///     container size changes
///   - How the scroll view should align content smaller than
///     its container size
///
/// You can further customize this behavior by assigning different unit
/// points for these different roles.
public struct ScrollAnchorRole: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case initialOffset, sizeChanges, alignment
    }

    let kind: Kind

    /// The role that influences where a scroll view should be
    /// initially scrolled.
    public static var initialOffset: ScrollAnchorRole { ScrollAnchorRole(kind: .initialOffset) }

    /// The role that influences how a scroll view should adjust its
    /// content offset when the scroll view's content or container size
    /// changes.
    public static var sizeChanges: ScrollAnchorRole { ScrollAnchorRole(kind: .sizeChanges) }

    /// The role that influences how a scroll view should align
    /// its content when the size of its content is smaller than the
    /// container size of the scroll view.
    public static var alignment: ScrollAnchorRole { ScrollAnchorRole(kind: .alignment) }
}

/// The anchors `.defaultScrollAnchor` set for the scroll view below: one
/// for every role, and one for each role on its own, which goes first.
struct ScrollAnchors: Equatable {
    var all: UnitPoint?
    /// `.some(nil)` sets a role's anchor to none, over `all`'s.
    var initialOffset: UnitPoint??
    var sizeChanges: UnitPoint??
    var alignment: UnitPoint??

    func anchor(for role: ScrollAnchorRole.Kind) -> UnitPoint? {
        switch role {
        case .initialOffset: initialOffset ?? all
        case .sizeChanges: sizeChanges ?? all
        case .alignment: alignment ?? all
        }
    }
}

private struct ScrollAnchorsKey: EnvironmentKey {
    static var defaultValue: ScrollAnchors { ScrollAnchors() }
}

extension EnvironmentValues {
    var scrollAnchors: ScrollAnchors {
        get { self[ScrollAnchorsKey.self] }
        set { self[ScrollAnchorsKey.self] = newValue }
    }
}

extension View {
    /// Associates an anchor to control which part of the scroll view's
    /// content should be rendered by default.
    ///
    /// Use this modifier to specify an anchor to control both which part of
    /// the scroll view's content should be visible initially and how
    /// the scroll view handles content size changes.
    ///
    /// Provide a value of `UnitPoint/center`` to have the scroll
    /// view start in the center of its content when a scroll view
    /// is scrollable in both axes.
    ///
    ///     ScrollView([.horizontal, .vertical]) {
    ///         // initially centered content
    ///     }
    ///     .defaultScrollAnchor(.center)
    ///
    /// Provide a value of `UnitPoint/bottom` to have the scroll view
    /// start at the bottom of its content when scrollable in the
    /// vertical axis.
    ///
    ///     ScrollView {
    ///         LazyVStack {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///     }
    ///     .defaultScrollAnchor(.bottom)
    ///
    /// The user may scroll away from the initial defined scroll position.
    /// When the content size of the scroll view changes, it may consult
    /// the anchor to know how to reposition the content: as far from the
    /// anchor's point of the scrollable range as it was — so at the bottom
    /// with `.bottom`, new content at the end keeps what was in view.
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        _ModifierView(content: self, modifier: DefaultScrollAnchorModifier(anchor: anchor))
    }

    /// Associates an anchor to control the position of a scroll view in a
    /// particular circumstance.
    ///
    /// You can associate a ``UnitPoint`` to a ``ScrollView`` using the
    /// ``View/defaultScrollAnchor(_:)`` modifier. By default, the system
    /// uses this point for different kinds of behaviors including:
    ///   - Where the scroll view should initially be scrolled
    ///   - How the scroll view should handle content size or
    ///     container size changes
    ///   - How the scroll view should align content smaller than
    ///     its container size
    ///
    /// You can further customize this behavior by assigning different unit
    /// points for these different cases.
    ///
    /// For example, you can use the ``View/defaultScrollAnchor(_:)`` modifier
    /// to provide a value of ``UnitPoint/bottom`` as the anchor for all cases
    /// and then opt out of certain cases by providing a different value
    /// for them.
    ///
    ///     ScrollView {
    ///         LazyVStack {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///     }
    ///     .defaultScrollAnchor(.bottom)
    ///     .defaultScrollAnchor(.topLeading, for: .alignment)
    public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View {
        _ModifierView(content: self, modifier: DefaultScrollAnchorRoleModifier(anchor: anchor, role: role))
    }
}

/// `.defaultScrollAnchor(_:)`.
struct DefaultScrollAnchorModifier: PrimitiveModifier, Equatable {
    let anchor: UnitPoint?

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.scrollAnchors.all = anchor
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}

/// `.defaultScrollAnchor(_:for:)`.
struct DefaultScrollAnchorRoleModifier: PrimitiveModifier, Equatable {
    let anchor: UnitPoint?
    let role: ScrollAnchorRole

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        switch role.kind {
        case .initialOffset: environment.scrollAnchors.initialOffset = .some(anchor)
        case .sizeChanges: environment.scrollAnchors.sizeChanges = .some(anchor)
        case .alignment: environment.scrollAnchors.alignment = .some(anchor)
        }
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}
