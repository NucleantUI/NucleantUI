//
//  NavigationTransition.swift
//  NucleantUI
//
//  How a `NavigationStack` moves from one screen to the next: the screen
//  being pushed says, with `.navigationTransition(_:)`, and the stack plays
//  it on the push and again, backwards, on the pop. `.automatic` slides the
//  new screen in over the old; `.zoom(sourceID:in:)` grows it out of a view
//  on the screen below, marked with `.matchedTransitionSource(id:in:)`.
//
//  A transition is a value, not code: what it is reaches the stack the way
//  a screen's title does (Navigation.swift), and the stack draws it — the
//  same on every platform (NavigationStackTransition.swift).
//

/// A style for the transition a `NavigationStack` plays when a screen is
/// pushed onto it or popped off it.
///
/// Set it on the destination with `.navigationTransition(_:)`.
public protocol NavigationTransition {
    /// What the transition is, for the stack to play.
    var _content: _NavigationTransitionContent { get }
}

/// What a `NavigationTransition` asks the stack for. Not for use by apps.
public struct _NavigationTransitionContent: Hashable {
    enum Kind: Hashable {
        /// The new screen slides in over the one below.
        case automatic
        /// The new screen grows out of the source marked with the same
        /// namespace and id on the screen below.
        case zoom(namespace: Namespace.ID, sourceID: AnyHashable)
    }

    let kind: Kind
}

/// The stack's own transition: the new screen slides in from the trailing
/// edge over the one below, which drifts the other way and dims.
public struct AutomaticNavigationTransition: NavigationTransition {
    public init() {}

    public var _content: _NavigationTransitionContent {
        _NavigationTransitionContent(kind: .automatic)
    }
}

/// The new screen grows out of a view on the screen below, and shrinks back
/// into it when popped.
public struct ZoomNavigationTransition: NavigationTransition {
    let namespace: Namespace.ID
    let sourceID: AnyHashable

    public var _content: _NavigationTransitionContent {
        _NavigationTransitionContent(kind: .zoom(namespace: namespace, sourceID: sourceID))
    }
}

extension NavigationTransition where Self == AutomaticNavigationTransition {
    /// The stack's own transition.
    public static var automatic: AutomaticNavigationTransition {
        AutomaticNavigationTransition()
    }
}

extension NavigationTransition where Self == ZoomNavigationTransition {
    /// The new screen zooms out of the view marked with
    /// `.matchedTransitionSource(id: sourceID, in: namespace)` on the screen
    /// it is pushed from — and back into it when popped. With no such view
    /// on screen, the stack plays `.automatic` instead.
    public static func zoom<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> ZoomNavigationTransition {
        ZoomNavigationTransition(namespace: namespace, sourceID: AnyHashable(sourceID))
    }
}

extension View {
    /// The transition the enclosing `NavigationStack` plays as this view's
    /// screen is pushed onto it and popped off it.
    ///
    /// Put it on the destination, outside any container:
    ///
    /// ```swift
    /// .navigationDestination(for: Photo.self) { photo in
    ///     PhotoDetail(photo)
    ///         .navigationTransition(.zoom(sourceID: photo.id, in: zoom))
    /// }
    /// ```
    public func navigationTransition<T: NavigationTransition>(_ style: T) -> some View {
        let content = style._content
        return _ModifierView(content: self, key: ["navigationTransition", content] as [AnyHashable]) { context in
            if let router = context.environment.navigationRouter,
               let screen = context.environment.navigationScreen {
                router.storage.setTransition(content, for: screen)
            }
            return EnvironmentContent(colorScheme: context.environment.colorScheme)
        }
    }
}

// MARK: - The source a zoom grows from

/// How a matched transition source looks: clipped to a rounded rectangle,
/// with a colour behind it. The colour also fills the shape that grows out
/// of it while it zooms.
public protocol MatchedTransitionSourceConfiguration: Sendable {
    /// Writes this configuration's part of the style.
    func _update(_ style: inout _MatchedTransitionSourceStyle)
}

/// A matched transition source's style, as its configurations leave it.
/// Not for use by apps.
public struct _MatchedTransitionSourceStyle: Hashable, Sendable {
    var background: Color?
    var cornerRadius: Double = 0
    var cornerStyle: RoundedCornerStyle = .circular
}

/// An unstyled matched transition source configuration.
public struct EmptyMatchedTransitionSourceConfiguration: MatchedTransitionSourceConfiguration {
    public func _update(_ style: inout _MatchedTransitionSourceStyle) {}
}

/// One configuration, then another: the later one wins where both set the
/// same thing.
struct CombinedMatchedTransitionSourceConfiguration<First: MatchedTransitionSourceConfiguration, Second: MatchedTransitionSourceConfiguration>: MatchedTransitionSourceConfiguration {
    let first: First
    let second: Second

    func _update(_ style: inout _MatchedTransitionSourceStyle) {
        first._update(&style)
        second._update(&style)
    }
}

struct ClipShapeSourceConfiguration: MatchedTransitionSourceConfiguration {
    let cornerRadius: Double
    let style: RoundedCornerStyle

    func _update(_ configuration: inout _MatchedTransitionSourceStyle) {
        configuration.cornerRadius = cornerRadius
        configuration.cornerStyle = style
    }
}

struct BackgroundSourceConfiguration: MatchedTransitionSourceConfiguration {
    let color: Color

    func _update(_ configuration: inout _MatchedTransitionSourceStyle) {
        configuration.background = color
    }
}

extension MatchedTransitionSourceConfiguration {
    /// Clips the source to `shape`. A zoom starts from these corners and
    /// rounds off to the screen's.
    public func clipShape(_ shape: RoundedRectangle) -> some MatchedTransitionSourceConfiguration {
        CombinedMatchedTransitionSourceConfiguration(
            first: self,
            second: ClipShapeSourceConfiguration(cornerRadius: shape.cornerRadius, style: shape.style)
        )
    }

    /// Draws `style` behind the source's content. While it zooms, the colour
    /// fills the shape that grows out of the source.
    public func background(_ style: Color) -> some MatchedTransitionSourceConfiguration {
        CombinedMatchedTransitionSourceConfiguration(first: self, second: BackgroundSourceConfiguration(color: style))
    }
}

extension View {
    /// Marks this view as where a `.zoom(sourceID: id, in: namespace)`
    /// navigation transition grows from, and shrinks back into.
    public func matchedTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace) { $0 }
    }

    /// The same, styled:
    ///
    /// ```swift
    /// Thumbnail(photo)
    ///     .matchedTransitionSource(id: photo.id, in: zoom) { source in
    ///         source
    ///             .clipShape(RoundedRectangle(cornerRadius: 12))
    ///             .background(.indigo)
    ///     }
    /// ```
    public func matchedTransitionSource<ID: Hashable, C: MatchedTransitionSourceConfiguration>(
        id: ID,
        in namespace: Namespace.ID,
        configuration: (EmptyMatchedTransitionSourceConfiguration) -> C
    ) -> some View {
        var style = _MatchedTransitionSourceStyle()
        configuration(EmptyMatchedTransitionSourceConfiguration())._update(&style)
        let key = MatchedTransitionSourceKey(namespace: namespace, id: AnyHashable(id))
        let resolved = style
        return _ModifierView(content: self, key: ["matchedTransitionSource", key, resolved] as [AnyHashable]) { context in
            MatchedTransitionSourceContent(
                key: key,
                style: resolved,
                storage: context.environment.navigationRouter?.storage,
                screen: context.environment.navigationScreen
            )
        }
    }
}

/// A source's namespace and id: what a zoom looks it up by.
struct MatchedTransitionSourceKey: Hashable {
    let namespace: Namespace.ID
    let id: AnyHashable
}

/// Where a marked source was last drawn, in window coordinates, and how.
struct MatchedTransitionSourceFrame {
    let frame: Rect
    let style: _MatchedTransitionSourceStyle
    /// The screen it is on, so it is forgotten with the screen.
    let screen: NavigationScreenID?
}

/// A marked source: draws its background and clips to its corners, files
/// where it is drawn with its stack every time it is drawn, and draws
/// nothing while a zoom stands in for it.
struct MatchedTransitionSourceContent: NodeContent {
    let key: MatchedTransitionSourceKey
    let style: _MatchedTransitionSourceStyle
    /// The enclosing stack's; `nil` outside any stack, where there is
    /// nothing to zoom into.
    let storage: NavigationStackStorage?
    let screen: NavigationScreenID?

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        if let storage {
            storage.noteSource(key, at: MatchedTransitionSourceFrame(frame: rect.applying(context.transform), style: style, screen: screen))
            if storage.hiddenSource == key {
                inner.opacity = 0
            }
        }
        if let background = style.background {
            list.append(.shape(ShapeDraw(
                path: Path { $0.addRect(rect, cornerRadius: style.cornerRadius) },
                bounds: rect,
                fill: inner.resolve(.color(background)),
                transform: inner.transform,
                clip: inner.clip,
                clipCornerRadius: inner.clipCornerRadius,
                transformedClips: inner.transformedClips
            )))
        }
        // Clipped only when rounded, as a source with square corners is
        // left as it draws.
        if style.cornerRadius > 0 {
            inner = inner.clipped(to: rect, cornerRadius: style.cornerRadius)
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}
