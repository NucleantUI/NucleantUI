//
//  ContentMargins.swift
//  NucleantUI
//
//  `.contentMargins`: margins a scroll view below insets its content by. The
//  content rests that far in from the scroll view's edges, and scrolls past
//  them — its offset goes before zero and beyond the content's end by as
//  much. A scroll view takes the margins for itself: the views inside it,
//  another scroll view among them, do not inherit them.
//

/// The placement of margins.
///
/// Different views can support customizating margins that appear in
/// different parts of that view. Use values of this type to customize
/// those margins of a particular placement.
///
/// For example, use a ``ContentMarginPlacement/scrollIndicators``
/// placement to customize the margins of scrollable view's scroll
/// indicators separately from the margins of a scrollable view's
/// content.
///
/// Use this type with the ``View/contentMargins(_:for:)`` modifier.
public struct ContentMarginPlacement: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case automatic, scrollContent, scrollIndicators
    }

    let kind: Kind

    /// The automatic placement.
    ///
    /// Views that support margin customization can automatically use
    /// margins with this placement. For example, a ``ScrollView`` will
    /// use this placement to automatically inset both its content and
    /// scroll indicators by the specified amount.
    public static var automatic: ContentMarginPlacement { ContentMarginPlacement(kind: .automatic) }

    /// The scroll content placement.
    ///
    /// Scrollable views like ``ScrollView`` will use this placement to
    /// inset their content, but not their scroll indicators.
    public static var scrollContent: ContentMarginPlacement { ContentMarginPlacement(kind: .scrollContent) }

    /// The scroll indicators placement.
    ///
    /// Scrollable views like ``ScrollView`` will use this placement to
    /// inset their scroll indicators, but not their content. There are no
    /// scroll indicators drawn yet, so nothing uses these margins so far.
    public static var scrollIndicators: ContentMarginPlacement { ContentMarginPlacement(kind: .scrollIndicators) }
}

/// The margins `.contentMargins` set, by placement, for the scroll view
/// below.
struct ContentMargins: Equatable {
    var scrollContent = EdgeInsets()
    var scrollIndicators = EdgeInsets()
}

private struct ContentMarginsKey: EnvironmentKey {
    static var defaultValue: ContentMargins { ContentMargins() }
}

extension EnvironmentValues {
    var contentMargins: ContentMargins {
        get { self[ContentMarginsKey.self] }
        set { self[ContentMarginsKey.self] = newValue }
    }
}

extension View {
    /// Configures the content margin for a provided placement.
    ///
    /// Use this modifier to customize the content margins of different
    /// kinds of views. For example, you can use this modifier to customize
    /// the margins of scrollable views like ``ScrollView``. In the
    /// following example, the scroll view will automatically inset
    /// its content by an additional 20 points on the leading and trailing
    /// edge.
    ///
    ///     ScrollView(.horizontal) {
    ///         // ...
    ///     }
    ///     .contentMargins(.horizontal, 20.0)
    ///
    /// You can provide a ``ContentMarginPlacement`` to target specific
    /// parts of a view to customize. For example, provide a
    /// ``ContentMarginPlacement/scrollContent`` placement to
    /// inset the content of a scroll view without affecting the
    /// insets of its scroll indicators.
    ///
    /// When applying multiple contentMargins modifiers, modifiers with
    /// the same placement will override modifiers higher up in the view
    /// hierarchy.
    ///
    /// - Parameters:
    ///   - edges: The edges to add the margins to.
    ///   - insets: The amount of margins to add.
    ///   - placement: Where the margins should be added.
    public func contentMargins(
        _ edges: Edge.Set = .all,
        _ insets: EdgeInsets,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        _ModifierView(content: self, modifier: ContentMarginsModifier(edges: edges, insets: insets, placement: placement))
    }

    /// Configures the content margin for a provided placement.
    ///
    /// Use this modifier to customize the content margins of different
    /// kinds of views. For example, you can use this modifier to customize
    /// the margins of scrollable views like ``ScrollView``.
    ///
    ///     ScrollView(.horizontal) {
    ///         // ...
    ///     }
    ///     .contentMargins(.horizontal, 20.0)
    ///
    /// When applying multiple contentMargins modifiers, modifiers with
    /// the same placement will override modifiers higher up in the view
    /// hierarchy.
    ///
    /// - Parameters:
    ///   - edges: The edges to add the margins to.
    ///   - length: The amount of margins to add; `nil` for the default
    ///     amount, 16 points, as `.padding`'s.
    ///   - placement: Where the margins should be added.
    public func contentMargins(
        _ edges: Edge.Set = .all,
        _ length: Double?,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        _ModifierView(content: self, modifier: ContentMarginsModifier(
            edges: edges,
            insets: EdgeInsets(.all, length ?? 16),
            placement: placement
        ))
    }

    /// Configures the content margin for a provided placement.
    ///
    /// Use this modifier to customize the content margins of different
    /// kinds of views. For example, you can use this modifier to customize
    /// the margins of scrollable views like ``ScrollView``.
    ///
    ///     ScrollView {
    ///         // ...
    ///     }
    ///     .contentMargins(10.0)
    ///
    /// When applying multiple contentMargins modifiers, modifiers with
    /// the same placement will override modifiers higher up in the view
    /// hierarchy.
    ///
    /// - Parameters:
    ///   - length: The amount of margins to add on all edges.
    ///   - placement: Where the margins should be added.
    public func contentMargins(_ length: Double, for placement: ContentMarginPlacement = .automatic) -> some View {
        _ModifierView(content: self, modifier: ContentMarginsModifier(
            edges: .all,
            insets: EdgeInsets(length),
            placement: placement
        ))
    }
}

/// `.contentMargins`: for each of `edges`, the margin of `insets` on that
/// edge, at `placement` — what was set above on the other edges is kept.
struct ContentMarginsModifier: PrimitiveModifier, Equatable {
    let edges: Edge.Set
    let insets: EdgeInsets
    let placement: ContentMarginPlacement

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        var margins = environment.contentMargins
        switch placement.kind {
        case .automatic:
            margins.scrollContent = replacing(margins.scrollContent)
            margins.scrollIndicators = replacing(margins.scrollIndicators)
        case .scrollContent:
            margins.scrollContent = replacing(margins.scrollContent)
        case .scrollIndicators:
            margins.scrollIndicators = replacing(margins.scrollIndicators)
        }
        environment.contentMargins = margins
    }

    /// `margins` with this modifier's edges replaced.
    private func replacing(_ margins: EdgeInsets) -> EdgeInsets {
        var result = margins
        if edges.contains(.top) { result.top = insets.top }
        if edges.contains(.leading) { result.leading = insets.leading }
        if edges.contains(.bottom) { result.bottom = insets.bottom }
        if edges.contains(.trailing) { result.trailing = insets.trailing }
        return result
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}
