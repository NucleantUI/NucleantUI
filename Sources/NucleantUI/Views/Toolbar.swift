//
//  Toolbar.swift
//  NucleantUI
//
//  `ToolbarContent` and its items: `ToolbarItem`, `ToolbarItemGroup`,
//  `ToolbarSpacer`, where each goes (`ToolbarItemPlacement`) and the
//  builder that lists them. `.toolbar { }` (NavigationModifiers.swift)
//  files what a screen lists with its `NavigationStack`, whose bars place
//  it (NavigationBarItems.swift).
//
//  The bars are the stack's own, drawn in the window the same way on every
//  platform: on macOS too, toolbar items go in the stack's bar, as on iOS,
//  not into the window's title bar.
//

/// Items for the bars of the enclosing `NavigationStack`, listed in
/// `.toolbar { }`.
///
/// ```swift
/// struct EditorToolbar: ToolbarContent {
///     var body: some ToolbarContent {
///         ToolbarItem(placement: .cancellationAction) { Button("Cancel") { … } }
///         ToolbarItem(placement: .confirmationAction) { Button("Save") { … } }
///     }
/// }
/// ```
@MainActor
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent

    @ToolbarContentBuilder var body: Body { get }

    /// Add this content's entries to `entries`, in the order it lists
    /// them. Composites go through `body`; the items append directly.
    func _lower(into entries: inout [ToolbarEntry])
}

extension ToolbarContent {
    public func _lower(into entries: inout [ToolbarEntry]) {
        body._lower(into: &entries)
    }
}

extension ToolbarContent where Body == Never {
    public var body: Never {
        preconditionFailure("body should not be called on the primitive toolbar content \(Self.self).")
    }
}

extension Never: ToolbarContent {}

/// One thing a `.toolbar` puts in a bar: a view, or a space between views.
public struct ToolbarEntry {
    enum Content {
        case view(AnyView)
        case spacer(SpacerSizing)
    }

    let placement: ToolbarItemPlacement
    let content: Content
}

/// Where a toolbar item goes in the enclosing stack's bars.
///
/// On a screen's navigation bar, left to right:
///
/// * leading: `.topBarLeading`, `.cancellationAction`, then `.navigation`
///   nearest the title, after the back button.
/// * the title's place: `.principal`, the first one, instead of the title.
/// * trailing: `.automatic`, `.topBarTrailing`, `.navigation` (on a pushed
///   screen, where the back button holds the leading edge),
///   `.primaryAction`, then `.confirmationAction` and `.destructiveAction`
///   at the trailing edge.
/// * `.secondaryAction`: in a "…" menu at the trailing edge.
///
/// `.bottomBar` and `.status` go in a bar along the bottom, a `.status`
/// item centred.
public struct ToolbarItemPlacement: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case automatic
        case principal
        case navigation
        case primaryAction
        case secondaryAction
        case status
        case confirmationAction
        case cancellationAction
        case destructiveAction
        case topBarLeading
        case topBarTrailing
        case bottomBar
    }

    let kind: Kind

    /// Where the bar puts items nobody placed: its trailing side.
    public static let automatic = ToolbarItemPlacement(kind: .automatic)
    /// The title's place, instead of the title.
    public static let principal = ToolbarItemPlacement(kind: .principal)
    /// A way around the app: leading, or trailing when the back button
    /// holds the leading edge.
    public static let navigation = ToolbarItemPlacement(kind: .navigation)
    /// The screen's most used action, trailing.
    public static let primaryAction = ToolbarItemPlacement(kind: .primaryAction)
    /// Actions used less often, in a "…" menu at the trailing edge.
    public static let secondaryAction = ToolbarItemPlacement(kind: .secondaryAction)
    /// What the screen's state is, centred in the bottom bar.
    public static let status = ToolbarItemPlacement(kind: .status)
    /// The action that confirms what the screen edits ("Save", "Done"), at
    /// the trailing edge.
    public static let confirmationAction = ToolbarItemPlacement(kind: .confirmationAction)
    /// The action that leaves without keeping the edits ("Cancel"),
    /// leading.
    public static let cancellationAction = ToolbarItemPlacement(kind: .cancellationAction)
    /// The action that deletes what the screen shows, at the trailing edge.
    public static let destructiveAction = ToolbarItemPlacement(kind: .destructiveAction)
    /// The leading side of the navigation bar.
    public static let topBarLeading = ToolbarItemPlacement(kind: .topBarLeading)
    /// The trailing side of the navigation bar.
    public static let topBarTrailing = ToolbarItemPlacement(kind: .topBarTrailing)
    /// The name `topBarLeading` had before.
    public static let navigationBarLeading = ToolbarItemPlacement(kind: .topBarLeading)
    /// The name `topBarTrailing` had before.
    public static let navigationBarTrailing = ToolbarItemPlacement(kind: .topBarTrailing)
    /// The bar along the bottom of the stack.
    public static let bottomBar = ToolbarItemPlacement(kind: .bottomBar)
}

/// One view in a bar, at a placement.
///
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .primaryAction) {
///         Button("Add") { list.add() }
///     }
/// }
/// ```
public struct ToolbarItem<ID, Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content

    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {
        entries.append(ToolbarEntry(placement: placement, content: .view(AnyView(content))))
    }
}

@MainActor
extension ToolbarItem where ID == () {
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

@MainActor
extension ToolbarItem where ID == String {
    /// An item named `id`. The name is for a toolbar the user rearranges,
    /// which NucleantUI's bars don't do yet; the item is placed as any
    /// other.
    public init(id: String, placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

/// Several views at one placement, side by side.
///
/// ```swift
/// ToolbarItemGroup(placement: .bottomBar) {
///     Button("Previous") { … }
///     Spacer()
///     Button("Next") { … }
/// }
/// ```
public struct ToolbarItemGroup<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content

    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {
        let row = HStack(spacing: NavigationBarItems.spacing) { content }
        entries.append(ToolbarEntry(placement: placement, content: .view(AnyView(row))))
    }
}

/// How much room a `ToolbarSpacer` takes.
public enum SpacerSizing: Hashable, Sendable {
    /// All there is, pushing the items on either side apart.
    case flexible
    /// A set gap, which parts the items on either side into two groups.
    case fixed
}

/// Room between toolbar items at one placement.
///
/// ```swift
/// ToolbarItem(placement: .bottomBar) { Button("Back") { … } }
/// ToolbarSpacer(.flexible, placement: .bottomBar)
/// ToolbarItem(placement: .bottomBar) { Button("Share") { … } }
/// ```
public struct ToolbarSpacer: ToolbarContent {
    let sizing: SpacerSizing
    let placement: ToolbarItemPlacement

    public init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) {
        self.sizing = sizing
        self.placement = placement
    }

    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {
        entries.append(ToolbarEntry(placement: placement, content: .spacer(sizing)))
    }
}

/// No toolbar content.
public struct EmptyToolbarContent: ToolbarContent {
    public init() {}

    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {}
}

/// Several items listed in one `@ToolbarContentBuilder` block.
public struct TupleToolbarContent<each Content: ToolbarContent>: ToolbarContent {
    public let value: (repeat each Content)

    public init(_ value: (repeat each Content)) {
        self.value = (repeat each value)
    }

    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {
        for content in repeat (each value) {
            content._lower(into: &entries)
        }
    }
}

/// A bare `if` in a builder: its items when the condition holds.
extension Optional: ToolbarContent where Wrapped: ToolbarContent {
    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {
        self?._lower(into: &entries)
    }
}

/// One branch of an `if`/`else` in a `@ToolbarContentBuilder`.
extension _ConditionalContent: ToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    public var body: Never { fatalError() }

    public func _lower(into entries: inout [ToolbarEntry]) {
        switch storage {
        case .trueContent(let content): content._lower(into: &entries)
        case .falseContent(let content): content._lower(into: &entries)
        }
    }
}

/// Lists toolbar items. Several make a `TupleToolbarContent`, `if`/`else`
/// a `_ConditionalContent`, a bare `if` an `Optional`.
@resultBuilder
@MainActor
public struct ToolbarContentBuilder {
    public static func buildExpression<Content: ToolbarContent>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock() -> EmptyToolbarContent {
        EmptyToolbarContent()
    }

    public static func buildBlock<Content: ToolbarContent>(_ content: Content) -> Content {
        content
    }

    /// Everything past one item. Parameter packs cover any number.
    @_disfavoredOverload
    public static func buildBlock<each Content: ToolbarContent>(
        _ content: repeat each Content
    ) -> TupleToolbarContent<repeat each Content> {
        TupleToolbarContent((repeat each content))
    }

    public static func buildIf<Content: ToolbarContent>(_ content: Content?) -> Content? {
        content
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .init(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .init(storage: .falseContent(second))
    }
}
