//
//  LayoutModifiers.swift
//  NucleantUI
//
//  Every modifier the framework draws itself is a `_ModifierView`: one
//  wrapped child, and the modifier — a small value of a type of its own,
//  one per SwiftUI modifier (`PaddingModifier` for `.padding`,
//  `FrameModifier` for `.frame(width:height:alignment:)`) — which says
//  which node it puts over the child and what it changes in the
//  environment below. `Text().padding().frame()` is
//  `_ModifierView<_ModifierView<Text, PaddingModifier>, FrameModifier>`:
//  the type says which modifiers, and two applications of one compare as
//  values of its type, field by field, resolved when it is compiled.
//

/// A modifier the framework draws itself.
@MainActor
protocol PrimitiveModifier: ViewInput {
    associatedtype Content: NodeContent

    /// The node it puts over the view it wraps — made under the
    /// environment `modifyEnvironment` left, before the view inside is
    /// built, so it can also adjust what that view is built with.
    func makeContent(_ context: inout BuildContext) -> Content

    /// What it changes in the environment for the view it wraps.
    func modifyEnvironment(_ environment: inout EnvironmentValues)
}

extension PrimitiveModifier {
    func modifyEnvironment(_ environment: inout EnvironmentValues) {}
}

extension PrimitiveModifier where Self: Equatable {
    /// Plain values: equal fields, the same modifier.
    func _isEquivalent(to other: Self) -> Bool {
        if _isPOD(Self.self), _plainBytesEqual(self, other) { return true }
        return self == other
    }
}

/// A view that wraps one child and contributes a specific layout node — the
/// one `modifier` makes.
public struct _ModifierView<Content: View, Modifier: ViewInput>: View {
    var content: Content
    let modifier: Modifier

    init(content: Content, modifier: Modifier) where Modifier: PrimitiveModifier {
        self.content = content
        self.modifier = modifier
    }

    public var body: Never { bodyUnavailable() }
}

extension _ModifierView {
    /// `Row().padding()` is one expression, so the builder stamps the
    /// outermost wrapper; the identity belongs to the view inside.
    public var _viewID: ViewID {
        get { content._viewID }
        set { content._viewID = newValue }
    }

    public func _isEquivalent(to other: _ModifierView<Content, Modifier>) -> Bool {
        modifier._isEquivalent(to: other.modifier) && _areEquivalent(content, other.content)
    }
}

extension _ModifierView: BuiltinView where Modifier: PrimitiveModifier {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        var inner = context
        modifier.modifyEnvironment(&inner.environment)
        let nodeContent = modifier.makeContent(&inner)
        let child = inner.child(0) { ctx in buildNode(content, &ctx) }
        let node = ContentNode(content: nodeContent, children: [child])
        // A `.transition` belongs to the whole modified view, wherever in
        // its chain of modifiers it was written.
        node.transitionTrait = nodeContent.transitionTrait ?? child.transitionTrait
        node.gridCellTraits = child.gridCellTraits
        node.layoutValues = child.layoutValues
        return node
    }
}

/// What a modifier that acts at build time and draws nothing of its own
/// puts in the tree (see `EnvironmentContent`).
extension PrimitiveModifier where Content == EnvironmentContent {
    func environmentContent(_ context: BuildContext) -> EnvironmentContent {
        EnvironmentContent()
    }
}

/// A view that wraps a child *and* a decoration — background and overlay.
public struct _DecoratedView<Content: View, Decoration: View>: View {
    var content: Content
    let decoration: Decoration
    let order: DecorationContent.Order
    let alignment: Alignment

    public var body: Never { bodyUnavailable() }

    /// As `_ModifierView`: the stamp belongs to the content.
    public var _viewID: ViewID {
        get { content._viewID }
        set { content._viewID = newValue }
    }

    public func _isEquivalent(to other: _DecoratedView<Content, Decoration>) -> Bool {
        order == other.order && alignment == other.alignment
            && _areEquivalent(content, other.content)
            && _areEquivalent(decoration, other.decoration)
    }
}

extension _DecoratedView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        // Two positional slots — `DecorationContent` reads `children[0]` and
        // `children[1]` directly and must not see them flattened.
        let contentNode = context.child(0) { ctx in buildNode(content, &ctx) }
        let decorationNode = context.child(1) { ctx in buildNode(decoration, &ctx) }
        let node = ContentNode(
            content: DecorationContent(order: order, alignment: alignment),
            children: [contentNode, decorationNode]
        )
        node.transitionTrait = contentNode.transitionTrait
        node.gridCellTraits = contentNode.gridCellTraits
        node.layoutValues = contentNode.layoutValues
        return node
    }
}

// MARK: - Frame

extension View {
    /// A fixed frame.
    public func frame(
        width: Double? = nil,
        height: Double? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _ModifierView(content: self, modifier: FrameModifier(width: width, height: height, alignment: alignment))
    }

    /// A flexible frame. `maxWidth: .infinity` means "take everything offered".
    public func frame(
        minWidth: Double? = nil,
        idealWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        idealHeight: Double? = nil,
        maxHeight: Double? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _ModifierView(content: self, modifier: FlexibleFrameModifier(
            minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
            minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
            alignment: alignment
        ))
    }
}

/// `.frame(width:height:alignment:)`.
struct FrameModifier: PrimitiveModifier, Equatable {
    let width: Double?
    let height: Double?
    let alignment: Alignment

    func makeContent(_ context: inout BuildContext) -> FrameContent {
        FrameContent(
            width: width,
            height: height,
            minWidth: nil,
            maxWidth: nil,
            minHeight: nil,
            maxHeight: nil,
            alignment: alignment
        )
    }
}

/// `.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
struct FlexibleFrameModifier: PrimitiveModifier, Equatable {
    let minWidth: Double?
    let idealWidth: Double?
    let maxWidth: Double?
    let minHeight: Double?
    let idealHeight: Double?
    let maxHeight: Double?
    let alignment: Alignment

    func makeContent(_ context: inout BuildContext) -> FrameContent {
        FrameContent(
            width: idealWidth,
            height: idealHeight,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight,
            alignment: alignment
        )
    }
}

extension View {
    /// Sizes this view to a fraction of the space its parent offers —
    /// `relativeSize(width: 0.4)` is "40% of the available width".
    ///
    /// A `nil` axis is left to the child.
    public func relativeSize(width: Double? = nil, height: Double? = nil) -> some View {
        _ModifierView(content: self, modifier: RelativeSizeModifier(width: width, height: height))
    }
}

/// `.relativeSize(width:height:)`.
struct RelativeSizeModifier: PrimitiveModifier, Equatable {
    let width: Double?
    let height: Double?

    func makeContent(_ context: inout BuildContext) -> RelativeSizeContent {
        RelativeSizeContent(widthFraction: width, heightFraction: height)
    }
}

// MARK: - Position

extension View {
    /// Positions the center of this view at `position` in its parent's
    /// coordinate space.
    ///
    /// The result takes all the space its parent offers — it is the space
    /// the point is measured in — and the view inside keeps its own size.
    public func position(_ position: Point) -> some View {
        _ModifierView(content: self, modifier: PositionModifier(position: position))
    }

    /// Positions the center of this view at `x`, `y` in its parent's
    /// coordinate space.
    public func position(x: Double = 0, y: Double = 0) -> some View {
        position(Point(x: x, y: y))
    }
}

/// `.position(_:)`.
struct PositionModifier: PrimitiveModifier, Equatable {
    let position: Point

    func makeContent(_ context: inout BuildContext) -> PositionContent {
        PositionContent(position: position)
    }
}

// MARK: - Padding

extension View {
    public func padding(_ insets: EdgeInsets) -> some View {
        _ModifierView(content: self, modifier: PaddingModifier(insets: insets))
    }

    public func padding(_ edges: Edge.Set = .all, _ amount: Double = 16) -> some View {
        padding(EdgeInsets(edges, amount))
    }

    public func padding(_ amount: Double) -> some View {
        padding(EdgeInsets(amount))
    }

    public func padding(horizontal: Double = 0, vertical: Double = 0) -> some View {
        padding(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
    }
}

extension View {
    /// Keeps this view in the tree — identity, `@State`, scroll offsets —
    /// while taking it off screen. Used by `NavigationStack` for the screens
    /// beneath the top one.
    public func _parked(_ isParked: Bool) -> some View {
        _ModifierView(content: self, modifier: ParkedModifier(isParked: isParked))
    }
}

/// `.padding(_:)`.
struct PaddingModifier: PrimitiveModifier, Equatable {
    let insets: EdgeInsets

    func makeContent(_ context: inout BuildContext) -> PaddingContent {
        PaddingContent(insets: insets)
    }
}

/// `._parked(_:)`.
struct ParkedModifier: PrimitiveModifier, Equatable {
    let isParked: Bool

    func makeContent(_ context: inout BuildContext) -> ParkedContent {
        ParkedContent(isParked: isParked)
    }
}
