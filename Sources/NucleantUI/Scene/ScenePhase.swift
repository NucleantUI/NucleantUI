//
//  ScenePhase.swift
//  NucleantUI
//

/// Where a scene is in the app's life: in use, set aside, or out of sight.
///
/// Read it from a view through the environment, and act when it changes:
///
/// ```swift
/// @View
/// struct TimerScreen {
///     let session: Session
///     @Environment(\.scenePhase) private var scenePhase
///
///     var body: some View {
///         Clock(session: session)
///             .onChange(of: scenePhase) { old, new in
///                 if new == .active { session.resume() } else if old == .active { session.pause() }
///             }
///     }
/// }
/// ```
///
/// A view gets the phase of the window it is in. What moves a window from
/// one phase to another is the platform's:
///
/// - On macOS a window is inactive while it is minimized and in the
///   background while the app is hidden; behind other windows, or with
///   another app in front, it is still active.
/// - On iOS a window goes as its scene: inactive in the app switcher, under
///   Control Center or a call, and on its way to or from the background;
///   in the background once it is off screen — another app, the Home
///   Screen, the device locked.
///
/// Where the platform doesn't say, the window stays active.
///
/// The phases are ordered: `background < inactive < active`.
public enum ScenePhase: Comparable, Hashable, Sendable {

    /// Out of sight. Nothing in the window is seen, and the window draws
    /// nothing until it comes back, so do as little as possible here —
    /// save what has to be saved, and stop what doesn't have to run.
    case background

    /// Still in the foreground, but not in use: no input reaches it, and
    /// its work — timers, animations, polling — can pause.
    case inactive

    /// In the foreground and in use.
    case active
}

private struct ScenePhaseKey: EnvironmentKey {
    static let defaultValue = ScenePhase.active
}

extension EnvironmentValues {
    /// The phase of the scene the view is in. The window seeds it and keeps
    /// it current; outside a window it is `.active`.
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}
