//
//  SystemBarModifiers.swift
//  NucleantUI
//
//  `.statusBarHidden(_:)` and `.persistentSystemOverlays(_:)`: what the
//  views want of the bars the system draws over the window. Each is a value
//  handed up the tree, like a preference; the host reads what reached its
//  root after every pass that built (`ViewHost.statusBarVisibility`,
//  `ViewHost.persistentSystemOverlays`), and the window passes it on to the
//  platform. `.toolbarVisibility(_:for: .statusBar)` sets the same value as
//  `.statusBarHidden(_:)`.
//
//  The view that asked deepest in the tree decides, so a screen can take
//  back what the app around it asked. Between views side by side, the last
//  one decides. A screen a `NavigationStack` keeps covered (parked) has no
//  say: the one on top decides, or the system's default when it asks
//  nothing.
//

extension View {

    /// Hides the status bar while this view is on screen, or shows it.
    ///
    /// ```swift
    /// PhotoViewer(photo: photo)
    ///     .statusBarHidden(isImmersive)
    /// ```
    ///
    /// The status bar is the system's, with the clock and the battery, on
    /// iOS and Android. Hidden, it gives its strip to the app, and the
    /// window's safe area shrinks with it. The other platforms have none,
    /// and nothing happens there.
    public func statusBarHidden(_ hidden: Bool = true) -> some View {
        _ModifierView(content: self, modifier: StatusBarHiddenModifier(hidden: hidden))
    }

    /// Hides or shows the system's persistent overlays while this view is
    /// on screen.
    ///
    /// ```swift
    /// VideoPlayer(movie: movie)
    ///     .persistentSystemOverlays(isPlaying ? .hidden : .automatic)
    /// ```
    ///
    /// On iOS that is the Home indicator, which then stays out of sight
    /// until a touch near it. On Android it is the navigation bar, hidden
    /// until a swipe in from the edge, and the window's safe area loses its
    /// strip. The other platforms have none, and nothing happens there.
    /// `.automatic` is the system's default: shown.
    public func persistentSystemOverlays(_ visibility: Visibility) -> some View {
        _ModifierView(content: self, modifier: PersistentSystemOverlaysModifier(visibility: visibility))
    }
}

// MARK: - Keys

/// Whether the status bar shows: `.statusBarHidden(_:)` and
/// `.toolbarVisibility(_:for: .statusBar)`.
struct StatusBarVisibilityKey: PreferenceKey {
    static let defaultValue = Visibility.automatic

    static func reduce(value: inout Visibility, nextValue: () -> Visibility) {
        value = nextValue()
    }
}

/// Whether the persistent system overlays show:
/// `.persistentSystemOverlays(_:)`.
struct PersistentSystemOverlaysKey: PreferenceKey {
    static let defaultValue = Visibility.automatic

    static func reduce(value: inout Visibility, nextValue: () -> Visibility) {
        value = nextValue()
    }
}

// MARK: - Modifiers

/// `.statusBarHidden(_:)`.
struct StatusBarHiddenModifier: PrimitiveModifier, Equatable {
    let hidden: Bool

    func makeContent(_ context: inout BuildContext) -> SystemBarContent<StatusBarVisibilityKey> {
        SystemBarContent(visibility: hidden ? .hidden : .visible)
    }
}

/// `.persistentSystemOverlays(_:)`.
struct PersistentSystemOverlaysModifier: PrimitiveModifier, Equatable {
    let visibility: Visibility

    func makeContent(_ context: inout BuildContext) -> SystemBarContent<PersistentSystemOverlaysKey> {
        SystemBarContent(visibility: visibility)
    }
}

// MARK: - Node

/// What a view asked of one of the window's system bars, for `K`. Its
/// subtree's own answer goes up in its place when there is one: the view
/// that asked deepest decides. `nil` asks nothing and passes the subtree's
/// answer through, as `.toolbarVisibility(_:for:)` does for bars other than
/// the status bar.
struct SystemBarContent<K: PreferenceKey>: NodeContent where K.Value == Visibility {
    let visibility: Visibility?

    func preference<Key: PreferenceKey>(_ key: Key.Type, below: Key.Value?) -> Key.Value? {
        guard key == K.self, below == nil, let visibility else { return below }
        return visibility as? Key.Value
    }
}
