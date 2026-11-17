//
//  ScrollDisabled.swift
//  NucleantUI
//
//  `.scrollDisabled`: scroll views below take no scroll from the user — no
//  finger, no wheel — through the environment, so every scroll view in the
//  hierarchy. One that is disabled is no scroll target at all: input goes
//  to a scroll view around it that is not. The app can still scroll it
//  (`ScrollViewReader`, `.scrollPosition`).
//

private struct IsScrollEnabledKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    /// A Boolean value that indicates whether any scroll views associated
    /// with this environment allow scrolling to occur.
    ///
    /// The default value is `true`. Use the ``View/scrollDisabled(_:)``
    /// modifier to configure this property.
    public var isScrollEnabled: Bool {
        get { self[IsScrollEnabledKey.self] }
        set { self[IsScrollEnabledKey.self] = newValue }
    }
}

extension View {
    /// Disables or enables scrolling in scrollable views.
    ///
    /// Use this modifier to control whether a ``ScrollView`` can scroll:
    ///
    /// ```swift
    /// @State private var isScrollDisabled = false
    ///
    /// var body: some View {
    ///     ScrollView {
    ///         VStack {
    ///             Toggle("Disable", isOn: $isScrollDisabled)
    ///             MyContent()
    ///         }
    ///     }
    ///     .scrollDisabled(isScrollDisabled)
    /// }
    /// ```
    ///
    /// NucleantUI passes the disabled property through the environment, which
    /// means you can use this modifier to disable scrolling for all scroll
    /// views within a view hierarchy. In the following example, the modifier
    /// affects both scroll views:
    ///
    /// ```swift
    /// ScrollView {
    ///     ForEach(rows) { row in
    ///         ScrollView(.horizontal) {
    ///             RowContent(row)
    ///         }
    ///     }
    /// }
    /// .scrollDisabled(true)
    /// ```
    ///
    /// You can also use this modifier to disable scrolling for other kinds
    /// of scrollable views, like a ``List``.
    ///
    /// As `.disabled(_:)` does, `false` keeps what the views around chose:
    /// a scroll view inside a disabled one is not enabled again by it. A
    /// drag under way when its scroll view is disabled is let go of where
    /// it is.
    ///
    /// - Parameter disabled: A Boolean that indicates whether scrolling is
    ///   disabled.
    public func scrollDisabled(_ disabled: Bool) -> some View {
        _ModifierView(content: self, modifier: ScrollDisabledModifier(disabled: disabled))
    }
}

struct ScrollDisabledModifier: PrimitiveModifier, Equatable {
    let disabled: Bool

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        if disabled { environment.isScrollEnabled = false }
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}
