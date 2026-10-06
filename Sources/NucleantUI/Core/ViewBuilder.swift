//
//  ViewBuilder.swift
//  NucleantUI
//

/// Constructs views from closures. Multi-statement blocks become a
/// `TupleView`; `if`/`else` becomes `_ConditionalContent`; a bare `if` becomes
/// an `Optional`.
@resultBuilder
@MainActor
public struct ViewBuilder {

    /// Every view expression in a body passes through here, and the implicit
    /// call sits on the expression — so a view whose initializer could not
    /// see its call site gets the expression's here. One that already has
    /// its own keeps it: that is the more precise of the two, and the only
    /// one that tells apart the two views of `flag ? Row("a") : Row("b")`,
    /// one expression with two call sites. The default setter on a plain
    /// `View` drops it, and that view is then identified by type and
    /// position alone. `#viewID` expands at that implicit call, to a
    /// literal: no string, no hashing, per expression per body run.
    public static func buildExpression<Content: View>(
        _ content: Content,
        _viewID: ViewID = #viewID
    ) -> Content {
        guard content._viewID == .unknown else { return content }
        var content = content
        content._viewID = _viewID
        return content
    }

    /// A primitive view's `body` is `Never`, and `View.body` carries
    /// `@ViewBuilder`, so `var body: Never { bodyUnavailable() }` is put
    /// through the transform like any other body. Without this overload it
    /// picks the generic one above, whose `#viewID` default argument is
    /// evaluated *after* the never-returning call it belongs to — code the
    /// compiler can see is unreachable, and a "will never be executed"
    /// warning at every primitive in the framework. There is nothing to
    /// stamp here anyway: the expression never produces a view.
    public static func buildExpression(_ content: Never) -> Never {}

    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    /// Everything past one child. Parameter packs cover any arity, so there is
    /// no 10-view ceiling the way there was before variadic generics.
    @_disfavoredOverload
    public static func buildBlock<each Content: View>(
        _ content: repeat each Content
    ) -> TupleView<repeat each Content> {
        TupleView((repeat each content))
    }

    public static func buildOptional<Content: View>(_ content: Content?) -> Content? {
        content
    }

    public static func buildIf<Content: View>(_ content: Content?) -> Content? {
        content
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .init(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .init(storage: .falseContent(second))
    }

    public static func buildArray<Content: View>(_ components: [Content]) -> _ViewArray<Content> {
        _ViewArray(components)
    }

    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView {
        AnyView(content)
    }
}
