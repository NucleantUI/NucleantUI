//
//  ScrollDismissesKeyboard.swift
//  NucleantUI
//
//  `.scrollDismissesKeyboard`: whether a finger scrolling a scroll view
//  puts the on-screen keyboard away — as the scroll begins, or as the
//  finger lets go moving the content down toward it — by taking the keys
//  from the text field that has them. Through the environment, so every
//  scroll view in the hierarchy.
//
//  Only where the platform shows a keyboard on screen for text (Android),
//  and only while one is up: a wheel, a trackpad, or a scroll the app asks
//  for never put it away, and on a desktop a scroll never takes the keys.
//

/// The ways that scrollable content can interact with the software keyboard.
///
/// Use this type in a call to the ``View/scrollDismissesKeyboard(_:)``
/// modifier to specify the dismissal behavior of scrollable views.
public struct ScrollDismissesKeyboardMode: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Hashable {
        case automatic, immediately, interactively, never
    }

    let kind: Kind

    /// Determine the mode automatically based on the surrounding context.
    ///
    /// A ``ScrollView``, and the ``List`` and ``Form`` that scroll in one,
    /// dismiss the keyboard as soon as a finger scrolls them.
    public static var automatic: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode(kind: .automatic) }

    /// Dismiss the keyboard as soon as scrolling starts.
    public static var immediately: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode(kind: .immediately) }

    /// Enable people to interactively dismiss the keyboard as part of the
    /// scroll operation.
    ///
    /// People dismiss the keyboard by letting go of the content while
    /// moving it down, toward the keyboard; reversing the direction of the
    /// scroll before letting go keeps it. The keyboard does not follow the
    /// finger on its way.
    public static var interactively: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode(kind: .interactively) }

    /// Never dismiss the keyboard automatically as a result of scrolling.
    public static var never: ScrollDismissesKeyboardMode { ScrollDismissesKeyboardMode(kind: .never) }
}

private struct ScrollDismissesKeyboardModeKey: EnvironmentKey {
    static var defaultValue: ScrollDismissesKeyboardMode { .automatic }
}

extension EnvironmentValues {
    /// The way that scrollable content interacts with the software keyboard.
    ///
    /// The default value is ``ScrollDismissesKeyboardMode/automatic``. Use the
    /// ``View/scrollDismissesKeyboard(_:)`` modifier to configure this
    /// property.
    public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode {
        get { self[ScrollDismissesKeyboardModeKey.self] }
        set { self[ScrollDismissesKeyboardModeKey.self] = newValue }
    }
}

extension View {
    /// Configures the behavior in which scrollable content interacts with
    /// the software keyboard.
    ///
    /// You use this modifier to customize how scrollable content interacts
    /// with the software keyboard. For example, you can specify a value of
    /// ``ScrollDismissesKeyboardMode/immediately`` to indicate that you
    /// would like scrollable content to immediately dismiss the keyboard if
    /// present when a scroll drag gesture begins.
    ///
    /// ```swift
    /// @State private var text = ""
    ///
    /// ScrollView {
    ///     TextField("Prompt", text: $text)
    ///     ForEach(0 ..< 50) { index in
    ///         Text("\(index)")
    ///             .padding()
    ///     }
    /// }
    /// .scrollDismissesKeyboard(.immediately)
    /// ```
    ///
    /// You can also use this modifier to customize the keyboard dismissal
    /// behavior for other kinds of scrollable views, like a ``List``.
    ///
    /// By default, scrollable content dismisses the keyboard as soon as a
    /// finger scrolls it. Pass a value of
    /// ``ScrollDismissesKeyboardMode/never`` to indicate that scrollable
    /// content should never automatically dismiss the keyboard.
    ///
    /// Dismissing the keyboard takes the keys from the text field that has
    /// them. It happens only where the platform shows a keyboard on screen,
    /// while one is up.
    ///
    /// - Parameter mode: The keyboard dismissal mode that scrollable content
    ///   uses.
    /// - Returns: A view that uses the specified keyboard dismissal mode.
    public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        _ModifierView(content: self, modifier: ScrollDismissesKeyboardModifier(mode: mode))
    }
}

struct ScrollDismissesKeyboardModifier: PrimitiveModifier, Equatable {
    let mode: ScrollDismissesKeyboardMode

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.scrollDismissesKeyboardMode = mode
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}
