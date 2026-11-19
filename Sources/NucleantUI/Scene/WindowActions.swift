//
//  WindowActions.swift
//  NucleantUI
//
//  `@Environment(\.openWindow)` and `@Environment(\.dismissWindow)`: what a
//  view calls to open one of the app's window scenes, or close windows.
//  Each window the app opens is handed both, wired to the app's windows
//  (`AppWindows`).
//

/// Opens a window from one of the app's scenes. Read it from the
/// environment and call it with the scene's id:
///
/// ```swift
/// @View
/// struct NewViewerButton {
///     @Environment(\.openWindow) private var openWindow
///
///     var body: some View {
///         Button("Open new mail viewer") {
///             openWindow(id: "mail-viewer")
///         }
///     }
/// }
/// ```
///
/// For a `WindowGroup` it opens another window from the group; for a
/// `Window` it opens the window, or brings it to the front when it is
/// already open.
public struct OpenWindowAction: Sendable {
    let open: @MainActor @Sendable (String) -> Void

    /// Opens a window from the scene whose id is `id`.
    @MainActor
    public func callAsFunction(id: String) {
        open(id)
    }
}

/// Closes windows the app opened. Read it from the environment:
///
/// ```swift
/// @View
/// struct DoneButton {
///     @Environment(\.dismissWindow) private var dismissWindow
///
///     var body: some View {
///         Button("Done") { dismissWindow() }
///     }
/// }
/// ```
public struct DismissWindowAction: Sendable {
    let dismiss: @MainActor @Sendable () -> Void
    let dismissID: @MainActor @Sendable (String) -> Void

    /// Closes the window this view is in.
    @MainActor
    public func callAsFunction() {
        dismiss()
    }

    /// Closes the window of the scene whose id is `id`: the `Window`, or
    /// every open window of the `WindowGroup`.
    @MainActor
    public func callAsFunction(id: String) {
        dismissID(id)
    }
}

private struct OpenWindowKey: EnvironmentKey {
    static let defaultValue = OpenWindowAction { id in
        nucleantLogError("NucleantUI: openWindow(id: \"\(id)\"): this view is in no window an app opened\n")
    }
}

private struct DismissWindowKey: EnvironmentKey {
    static let defaultValue = DismissWindowAction(
        dismiss: {
            nucleantLogError("NucleantUI: dismissWindow(): this view is in no window an app opened\n")
        },
        dismissID: { id in
            nucleantLogError("NucleantUI: dismissWindow(id: \"\(id)\"): this view is in no window an app opened\n")
        }
    )
}

private struct SupportsMultipleWindowsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the app can have more than one window open: `true` on macOS,
    /// `false` elsewhere so far, and for a view in no window an app opened.
    /// Where it is `false`, `openWindow` past the app's first window opens
    /// nothing and logs why.
    ///
    /// ```swift
    /// Button("Open New Window") { openWindow(id: "mail-viewer") }
    ///     .disabled(!supportsMultipleWindows)
    /// ```
    public internal(set) var supportsMultipleWindows: Bool {
        get { self[SupportsMultipleWindowsKey.self] }
        set { self[SupportsMultipleWindowsKey.self] = newValue }
    }

    /// Opens a window from one of the app's scenes, by its id.
    public var openWindow: OpenWindowAction {
        get { self[OpenWindowKey.self] }
        set { self[OpenWindowKey.self] = newValue }
    }

    /// Closes the window the view is in, or the windows of a scene by its
    /// id.
    public var dismissWindow: DismissWindowAction {
        get { self[DismissWindowKey.self] }
        set { self[DismissWindowKey.self] = newValue }
    }
}
