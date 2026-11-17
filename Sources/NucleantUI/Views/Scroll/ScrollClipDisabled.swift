//
//  ScrollClipDisabled.swift
//  NucleantUI
//
//  `.scrollClipDisabled`: scroll views below draw their content past their
//  own edges — the shadows of the cards in a shelf, the neighbors peeking
//  in from either side. Through the environment, so every scroll view in
//  the hierarchy.
//
//  Past the edges is still not everywhere: the content is cut one viewport
//  out each way (and by whatever clips around the scroll view). That is
//  also how far a lazy stack inside builds its rows, which it decides from
//  the clip — with none at all it would build every one. What is drawn
//  outside the scroll view takes no taps; only its own frame does.
//

private struct ScrollClipDisabledKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether scroll views here draw their content past their edges
    /// (`.scrollClipDisabled`).
    var scrollClipDisabled: Bool {
        get { self[ScrollClipDisabledKey.self] }
        set { self[ScrollClipDisabledKey.self] = newValue }
    }
}

extension View {
    /// Sets whether a scroll view clips its content to its bounds.
    ///
    /// By default, a scroll view clips its content to its bounds, but you can
    /// disable that behavior by using this modifier. For example, if the views
    /// inside the scroll view have shadows that extend beyond the bounds of the
    /// scroll view, you can use this modifier to avoid clipping the shadows:
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     var disabled: Bool
    ///     let colors: [Color] = [.red, .green, .blue, .mint, .teal]
    ///
    ///     var body: some View {
    ///         ScrollView(.horizontal) {
    ///             HStack(spacing: 20) {
    ///                 ForEach(colors, id: \.self) { color in
    ///                     Rectangle()
    ///                         .frame(width: 100, height: 100)
    ///                         .foregroundStyle(color)
    ///                         .shadow(color: .primary, radius: 20)
    ///                 }
    ///             }
    ///         }
    ///         .scrollClipDisabled(disabled)
    ///     }
    /// }
    /// ```
    ///
    /// While you might want to avoid clipping parts of views that exceed the
    /// bounds of the scroll view, like the shadows in the above example, you
    /// typically still want the scroll view to clip at some point.
    /// Create custom clipping by using the ``View/clipShape(_:)``
    /// modifier to add a different clip shape. The following code disables
    /// the default clipping and then adds rectangular clipping that exceeds
    /// the bounds of the scroll view by the default padding amount:
    ///
    /// ```swift
    /// ScrollView(.horizontal) {
    ///     // ...
    /// }
    /// .scrollClipDisabled()
    /// .padding()
    /// .clipShape(Rectangle())
    /// ```
    ///
    /// The content is still cut one scroll view's size out from each of its
    /// edges, which is as far as a lazy stack inside builds; and what is
    /// drawn outside the scroll view takes no taps.
    ///
    /// - Parameter disabled: A Boolean value that specifies whether to disable
    ///   scroll view clipping.
    /// - Returns: A view that disables or enables scroll view clipping.
    public func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        _ModifierView(content: self, modifier: ScrollClipDisabledModifier(disabled: disabled))
    }
}

struct ScrollClipDisabledModifier: PrimitiveModifier, Equatable {
    let disabled: Bool

    func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.scrollClipDisabled = disabled
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }
}
