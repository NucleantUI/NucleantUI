//
//  WindowInput.swift
//  NucleantUI
//
//  The window's input as the platform reports it, before the view tree's
//  hit testing, gestures and focus see it — for a view that runs something
//  of its own inside it (another UI toolkit) and wants the pointer and the
//  keys as they come.
//

import NucleantWindow

/// Hears a window's input before its views do. Each method gets one event,
/// in the window's points (origin top-left), and returns whether it took it:
/// `true` keeps it from the views, `false` lets them have it. Every method
/// returns `false` unless implemented.
///
/// ```swift
/// @Environment(\.windowInput) var windowInput
/// …
/// .onAppear { windowInput?.delegate = session }
/// ```
@MainActor
public protocol WindowInputDelegate: AnyObject {
    func windowMouseDown(at point: Point, modifiers: EventModifiers) -> Bool
    func windowMouseUp(at point: Point) -> Bool
    /// The mouse moved with its button down.
    func windowMouseDragged(to point: Point) -> Bool
    /// The mouse moved with no button down.
    func windowMouseMoved(to point: Point) -> Bool
    func windowRightMouseDown(at point: Point) -> Bool
    func windowRightMouseUp(at point: Point) -> Bool
    /// A wheel or trackpad delta, in points, with the mouse at `point`.
    func windowScroll(dx: Double, dy: Double, at point: Point) -> Bool
    /// `keyCode` is the platform's virtual key code (`NSEvent.keyCode`).
    func windowKeyDown(keyCode: UInt16, characters: String?, modifiers: EventModifiers) -> Bool
    func windowKeyUp(keyCode: UInt16, characters: String?, modifiers: EventModifiers) -> Bool
    func windowMagnify(phase: TrackpadGesturePhase, delta: Double, at point: Point) -> Bool
    func windowRotate(phase: TrackpadGesturePhase, delta: Double, at point: Point) -> Bool
    /// A finger, `id` telling it from the others down at the same time.
    func windowTouchDown(id: Int, at point: Point) -> Bool
    func windowTouchMoved(id: Int, to point: Point) -> Bool
    func windowTouchUp(id: Int, at point: Point) -> Bool
    func windowTouchCancelled(id: Int, at point: Point) -> Bool
}

extension WindowInputDelegate {
    public func windowMouseDown(at point: Point, modifiers: EventModifiers) -> Bool { false }
    public func windowMouseUp(at point: Point) -> Bool { false }
    public func windowMouseDragged(to point: Point) -> Bool { false }
    public func windowMouseMoved(to point: Point) -> Bool { false }
    public func windowRightMouseDown(at point: Point) -> Bool { false }
    public func windowRightMouseUp(at point: Point) -> Bool { false }
    public func windowScroll(dx: Double, dy: Double, at point: Point) -> Bool { false }
    public func windowKeyDown(keyCode: UInt16, characters: String?, modifiers: EventModifiers) -> Bool { false }
    public func windowKeyUp(keyCode: UInt16, characters: String?, modifiers: EventModifiers) -> Bool { false }
    public func windowMagnify(phase: TrackpadGesturePhase, delta: Double, at point: Point) -> Bool { false }
    public func windowRotate(phase: TrackpadGesturePhase, delta: Double, at point: Point) -> Bool { false }
    public func windowTouchDown(id: Int, at point: Point) -> Bool { false }
    public func windowTouchMoved(id: Int, to point: Point) -> Bool { false }
    public func windowTouchUp(id: Int, at point: Point) -> Bool { false }
    public func windowTouchCancelled(id: Int, at point: Point) -> Bool { false }
}

/// A window's input, as its views reach it: `@Environment(\.windowInput)`.
/// Its `delegate` hears every event first. One per window, for its lifetime.
@MainActor
public final class WindowInput {
    public weak var delegate: WindowInputDelegate?

    init() {}
}

extension WindowInput: ViewInput {
    /// One per window, for its lifetime.
    public func _isEquivalent(to other: WindowInput) -> Bool {
        self === other
    }
}

private struct WindowInputKey: EnvironmentKey {
    static let defaultValue: WindowInput? = nil
}

extension EnvironmentValues {
    /// The input of the window the view is in — `nil` in a tree hosted
    /// without one.
    public var windowInput: WindowInput? {
        get { self[WindowInputKey.self] }
        set { self[WindowInputKey.self] = newValue }
    }
}
