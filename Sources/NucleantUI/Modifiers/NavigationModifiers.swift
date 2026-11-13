//
//  NavigationModifiers.swift
//  NucleantUI
//
//  Each files something with the enclosing `NavigationStack` while it
//  builds, through the router in the environment — the stack reads it back
//  when it builds its screens and its bar.
//

/// A bar a container draws, for `.toolbarVisibility(_:for:)` to name.
public struct ToolbarPlacement: Hashable, Sendable {
    enum Bar: Hashable, Sendable {
        case automatic
        case navigationBar
        case bottomBar
    }

    let bar: Bar

    /// The container's main bar — inside a `NavigationStack`, its
    /// navigation bar.
    public static let automatic = ToolbarPlacement(bar: .automatic)

    /// The bar across the top of a `NavigationStack`: the title and the
    /// back button.
    public static let navigationBar = ToolbarPlacement(bar: .navigationBar)

    /// The bar along the bottom of a `NavigationStack`, with the screen's
    /// `.bottomBar` and `.status` items.
    public static let bottomBar = ToolbarPlacement(bar: .bottomBar)
}

/// Stands in for a view type in the keys `.toolbar` and
/// `.navigationBarBackButtonHidden` take their leave by.
private enum ToolbarMarker {}
private enum BackButtonHiddenMarker {}

extension View {

    /// Shows values of type `D` pushed onto the enclosing stack as
    /// `destination(value)`.
    ///
    /// ```swift
    /// List…
    ///     .navigationDestination(for: Recipe.self) { recipe in
    ///         RecipeDetail(recipe: recipe)
    ///     }
    /// ```
    ///
    /// Put it on the stack's root or on a screen below the ones it serves:
    /// screens are built bottom first, so a destination declared on a
    /// screen above isn't known yet when one below it is resolved.
    public func navigationDestination<D: Hashable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        // No key: the closure can't be compared, so this re-registers every
        // time its parent re-runs, and the stack always resolves with the
        // latest one.
        _ModifierView(content: self, modifier: NavigationDestinationModifier(destination: destination))
    }

    /// The title the enclosing stack's bar shows while this view's screen
    /// is on top.
    public func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        navigationTitle(String(title))
    }

    public func navigationTitle(_ title: Text) -> some View {
        navigationTitle(title.content)
    }

    private func navigationTitle(_ title: String) -> some View {
        _ModifierView(content: self, modifier: NavigationTitleModifier(title: title))
    }

    /// Shows or hides the enclosing stack's bar while this view's screen is
    /// on top.
    ///
    /// ```swift
    /// PhotoViewer(photo: photo)
    ///     .toolbarVisibility(isImmersive ? .hidden : .visible, for: .navigationBar)
    /// ```
    ///
    /// The screen gets the stack's whole height while the bar is hidden.
    /// The back button goes with it, so give the screen its own way back
    /// (`navigationRouter.pop()`). No `bars` means `.automatic`, and
    /// `.automatic` visibility shows the bar. Other screens keep their own
    /// setting: hiding the bar on a pushed screen brings it back when that
    /// screen is popped.
    public func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        navigationBarVisibility(visibility, for: bars)
    }

    /// The name `toolbarVisibility(_:for:)` had before SwiftUI renamed it.
    public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        navigationBarVisibility(visibility, for: bars)
    }

    private func navigationBarVisibility(_ visibility: Visibility, for bars: [ToolbarPlacement]) -> some View {
        _ModifierView(content: self, modifier: ToolbarVisibilityModifier(
            visibility: visibility,
            bars: bars.isEmpty ? [.automatic] : bars
        ))
    }

    /// Items for the enclosing stack's bars while this view's screen is on
    /// top.
    ///
    /// ```swift
    /// NoteEditor(note: note)
    ///     .toolbar {
    ///         ToolbarItem(placement: .cancellationAction) { Button("Cancel") { … } }
    ///         ToolbarItem(placement: .confirmationAction) { Button("Save") { … } }
    ///     }
    /// ```
    ///
    /// Each item is built in this view's environment. Several `.toolbar`s
    /// on one screen add up: an outer one's items before an inner one's,
    /// and siblings' in the order they are written. A `.toolbar` outside
    /// any stack's screen shows nothing.
    ///
    /// The bars are the stack's own, on every platform: on macOS the items
    /// go in the stack's bar too, not in the window's title bar.
    public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        var entries: [ToolbarEntry] = []
        content()._lower(into: &entries)
        return fileToolbar(entries)
    }

    /// Views for the enclosing stack's bar, on its trailing side — as
    /// `ToolbarItem`s with the `.automatic` placement.
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let row = HStack(spacing: NavigationBarItems.spacing) { content() }
        return fileToolbar([ToolbarEntry(placement: .automatic, content: .view(AnyView(row)))])
    }

    private func fileToolbar(_ entries: [ToolbarEntry]) -> some View {
        // No key: the items' views can't be compared, so this files them
        // again every time its parent re-runs, and the bar shows the latest.
        _ModifierView(content: self, modifier: ToolbarModifier(entries: entries))
    }

    /// Hides the back button of the enclosing stack's bar while this view's
    /// screen is on top, and keeps the bar.
    ///
    /// ```swift
    /// DetailScreen()
    ///     .navigationBarBackButtonHidden()
    ///     .toolbar {
    ///         ToolbarItem(placement: .navigation) {
    ///             Button("Close") { router?.pop() }
    ///         }
    ///     }
    /// ```
    ///
    /// The way to a back button of your own: hide this one and put yours in
    /// the `.navigation` placement, which then takes the leading edge.
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        _ModifierView(content: self, modifier: BackButtonHiddenModifier(hidesBackButton: hidesBackButton))
    }
}

// MARK: - The modifiers
//
// Each files what it says with the enclosing stack as it is built, and
// puts nothing of its own in the tree (`EnvironmentContent`).

/// `.navigationDestination(for:destination:)`. Built again whenever its
/// parent is: the closure can't be compared, so it registers again, and
/// the stack always resolves with the latest one.
struct NavigationDestinationModifier<D: Hashable, C: View>: PrimitiveModifier {
    let destination: (D) -> C

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        let destination = self.destination
        context.environment.navigationRouter?.storage.register(D.self) { value in
            AnyView(destination(value))
        }
        return environmentContent(context)
    }

    func _isEquivalent(to other: NavigationDestinationModifier<D, C>) -> Bool { false }
}

/// `.navigationTitle(_:)`.
struct NavigationTitleModifier: PrimitiveModifier, Equatable {
    let title: String

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        if let router = context.environment.navigationRouter,
           let screen = context.environment.navigationScreen {
            router.storage.setTitle(title, for: screen)
        }
        return environmentContent(context)
    }
}

/// `.toolbarVisibility(_:for:)` and `.toolbar(_:for:)`.
struct ToolbarVisibilityModifier: PrimitiveModifier, Equatable {
    let visibility: Visibility
    let bars: [ToolbarPlacement]

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        if let router = context.environment.navigationRouter,
           let screen = context.environment.navigationScreen {
            // `.automatic` is a stack's main bar, the navigation bar.
            if bars.contains(.automatic) || bars.contains(.navigationBar) {
                router.storage.setBarVisibility(visibility, for: screen)
            }
            if bars.contains(.bottomBar) {
                router.storage.setBottomBarVisibility(visibility, for: screen)
            }
        }
        return environmentContent(context)
    }
}

/// The `.toolbar` modifiers. Built again whenever their parent is: the
/// items' views can't be compared, so they are filed again, and the bar
/// shows the latest.
struct ToolbarModifier: PrimitiveModifier {
    let entries: [ToolbarEntry]

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        if let router = context.environment.navigationRouter,
           let screen = context.environment.navigationScreen {
            let storage = router.storage
            let path = context.path
            storage.setToolbar(entries, environment: context.environment, at: path, for: screen)
            // Gone from the tree (an `if` turned false), its items go
            // from the bar.
            context.effects.onDisappear(
                StateKey(path: path, propertyIndex: -1, viewType: ObjectIdentifier(ToolbarMarker.self))
            ) {
                storage.removeToolbar(at: path, for: screen)
            }
        }
        return environmentContent(context)
    }

    func _isEquivalent(to other: ToolbarModifier) -> Bool { false }
}

/// `.navigationBarBackButtonHidden(_:)`.
struct BackButtonHiddenModifier: PrimitiveModifier, Equatable {
    let hidesBackButton: Bool

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        if let router = context.environment.navigationRouter,
           let screen = context.environment.navigationScreen {
            let storage = router.storage
            let path = context.path
            storage.setBackButtonHidden(hidesBackButton, at: path, for: screen)
            context.effects.onDisappear(
                StateKey(path: path, propertyIndex: -1, viewType: ObjectIdentifier(BackButtonHiddenMarker.self))
            ) {
                storage.removeBackButtonHidden(at: path, for: screen)
            }
        }
        return environmentContent(context)
    }
}
