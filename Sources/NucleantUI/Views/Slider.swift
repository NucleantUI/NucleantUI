//
//  Slider.swift
//  NucleantUI
//

/// A control for picking a value from a continuous range.
///
/// ```swift
/// Slider(value: $volume)
///
/// Slider(value: $tempo, in: 60...200, step: 1) {
///     Text("Tempo")
/// } minimumValueLabel: {
///     Text("60")
/// } maximumValueLabel: {
///     Text("200")
/// } onEditingChanged: { editing in
///     isScrubbing = editing
/// }
/// ```
///
/// A press on the track jumps the knob there and a drag moves it; with a
/// `step`, the value snaps to the nearest step from the lower bound. The
/// filled part of the track is the tint. The label sits before the track,
/// the value labels at either end of it.
///
/// A slider made without a label — `Slider(value: $volume)`, or with only
/// value labels — or with a blank one (`EmptyView`, or a `Text("")`) keeps
/// no room for it: the track starts and ends at the labels there are.
@View
public struct Slider<Label: View, ValueLabel: View> {
    /// The caller's value, as a `Double` — the value type is only generic in
    /// the initializers, as in SwiftUI.
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double?
    let label: Label
    let minimumValueLabel: ValueLabel
    let maximumValueLabel: ValueLabel
    let onEditingChanged: (Bool) -> Void

    @Environment(\.tint) private var tint
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labelsHidden) private var labelsHidden
    @State private var isEditing = false

    private static var knobDiameter: Double { 20 }

    init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        bounds: ClosedRange<V>,
        step: V.Stride?,
        label: Label,
        minimumValueLabel: ValueLabel,
        maximumValueLabel: ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void,
        _viewID: ViewID
    ) where V.Stride: BinaryFloatingPoint {
        // Keeps the caller's source, so two sliders over the same value are
        // the same input.
        self._value = Binding<Double>(
            source: value.source,
            get: { _ in Double(value.wrappedValue) },
            set: { newValue, _ in value.wrappedValue = V(newValue) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = step.map { Double($0) }
        self.label = label
        self.minimumValueLabel = minimumValueLabel
        self.maximumValueLabel = maximumValueLabel
        self.onEditingChanged = onEditingChanged
        self._viewID = _viewID
    }

    public var body: some View {
        HStack(spacing: 8) {
            if !labelsHidden && !isBlank(label) {
                label
            }
            if !isBlank(minimumValueLabel) {
                minimumValueLabel
            }
            _SliderTrack(
                fraction: fraction,
                fill: isEnabled ? tint : AnyShapeStyle(controlTrackColor),
                knobDiameter: Self.knobDiameter
            )
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        if !isEditing {
                            isEditing = true
                            onEditingChanged(true)
                        }
                        set(fractionAt: drag.location.x, width: drag.bounds.width)
                    }
                    .onEnded { drag in
                        set(fractionAt: drag.location.x, width: drag.bounds.width)
                        isEditing = false
                        onEditingChanged(false)
                    }
            )
            if !isBlank(maximumValueLabel) {
                maximumValueLabel
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    /// Whether a label shows nothing: an `EmptyView`, as a slider made
    /// without one has, or a text with no characters. A blank label is left
    /// out along with the room beside it, so the track starts and ends at
    /// the labels there are.
    private func isBlank<V: View>(_ view: V) -> Bool {
        if V.self == EmptyView.self { return true }
        if let text = view as? Text { return text.content.isEmpty }
        return false
    }

    /// Where the value sits along the range, 0…1.
    private var fraction: Double {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - bounds.lowerBound) / span))
    }

    /// Set the value from a point `x` along a track `width` wide. The knob's
    /// centre travels between one radius in from either end, so the ends of
    /// the range are reachable with the whole knob still on the track.
    private func set(fractionAt x: Double, width: Double) {
        let radius = Self.knobDiameter / 2
        let travel = width - 2 * radius
        guard travel > 0 else { return }
        let fraction = min(1, max(0, (x - radius) / travel))
        var newValue = bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound)
        if let step, step > 0 {
            newValue = bounds.lowerBound + ((newValue - bounds.lowerBound) / step).rounded() * step
            newValue = min(bounds.upperBound, max(bounds.lowerBound, newValue))
        }
        if newValue != value { value = newValue }
    }
}

// MARK: - Initializers

@MainActor
extension Slider {
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil,
            label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }

    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: step,
            label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }
}

@MainActor
extension Slider where ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil,
            label: label(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }

    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: step,
            label: label(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }
}

@MainActor
extension Slider where Label == EmptyView {
    /// Creates a slider with value labels at either end of the track but no
    /// label before it.
    ///
    /// ```swift
    /// Slider(value: $volume) {
    ///     Text("0%")
    /// } maximumValueLabel: {
    ///     Text("100%")
    /// }
    /// ```
    ///
    /// SwiftUI has no slider with value labels and no label; there, the
    /// label is hidden with `.labelsHidden()`.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        _viewID: ViewID = #viewID,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil,
            label: EmptyView(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }

    /// Creates a slider stepping by `step`, with value labels at either end
    /// of the track but no label before it.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        _viewID: ViewID = #viewID,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: step,
            label: EmptyView(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }
}

@MainActor
extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        _viewID: ViewID = #viewID,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil,
            label: EmptyView(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }

    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        _viewID: ViewID = #viewID,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: step,
            label: EmptyView(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }
}

@MainActor
extension Slider {
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        minimumValueLabel: ValueLabel,
        maximumValueLabel: ValueLabel,
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil,
            label: label(), minimumValueLabel: minimumValueLabel, maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }

    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        minimumValueLabel: ValueLabel,
        maximumValueLabel: ValueLabel,
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: step,
            label: label(), minimumValueLabel: minimumValueLabel, maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }
}

/// The older order, `onEditingChanged` before the label. `Slider(value:) {
/// Text("Volume") }` fits these as well as the ones above, so they give way
/// to those: they are only picked when nothing else fits.
@MainActor
extension Slider where ValueLabel == EmptyView {
    @_disfavoredOverload
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: nil,
            label: label(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }

    @_disfavoredOverload
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        _viewID: ViewID = #viewID,
        @ViewBuilder label: () -> Label
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, bounds: bounds, step: step,
            label: label(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(),
            onEditingChanged: onEditingChanged, _viewID: _viewID
        )
    }
}

// MARK: - Track

/// The track, its filled part and the knob — laid out by
/// `SliderTrackContent`, which alone knows the width the knob's position is
/// a fraction of.
@View
struct _SliderTrack {
    let fraction: Double
    let fill: AnyShapeStyle
    let knobDiameter: Double

    var body: Never { bodyUnavailable() }
}

extension _SliderTrack: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let track = context.child(0) { ctx in buildNode(Capsule().fill(controlTrackColor), &ctx) }
        let filled = context.child(1) { ctx in buildNode(Capsule().fill(fill), &ctx) }
        let knob = context.child(2) { ctx in
            buildNode(
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(.separator, lineWidth: 1)),
                &ctx
            )
        }
        return ContentNode(
            content: SliderTrackContent(fraction: fraction, knobDiameter: knobDiameter),
            children: [track, filled, knob]
        )
    }
}

/// Takes the width it is offered and the knob's height. The track runs the
/// full width, 4pt tall and centred; the fill runs from its leading end to
/// the knob's centre; the knob's centre travels between one radius in from
/// either end.
struct SliderTrackContent: NodeContent {
    let fraction: Double
    let knobDiameter: Double

    private static var trackHeight: Double { 4 }
    /// Its width when offered none — inside a horizontal scroll view, say.
    private static var idealWidth: Double { 160 }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        let width = proposal.width.map { $0.isFinite ? $0 : Self.idealWidth } ?? Self.idealWidth
        return Size(width: max(knobDiameter, width), height: knobDiameter)
    }

    /// Stretches along a row, like a `Spacer`; fixed across it.
    func flexibility(along axis: Axis, node: ViewNode) -> LayoutPriorityClass {
        axis == .horizontal ? .flexible : .fixed
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let children = node.children
        guard children.count == 3 else { return }
        let radius = knobDiameter / 2
        let centerX = rect.minX + radius + max(0, rect.width - knobDiameter) * fraction
        let trackY = rect.midY - Self.trackHeight / 2

        let track = Rect(x: rect.minX, y: trackY, width: rect.width, height: Self.trackHeight)
        children[0].place(in: track, proposal: ProposedSize(track.size), context: context, into: &list)

        let filled = Rect(x: rect.minX, y: trackY, width: centerX - rect.minX, height: Self.trackHeight)
        children[1].place(in: filled, proposal: ProposedSize(filled.size), context: context, into: &list)

        let knob = Rect(x: centerX - radius, y: rect.midY - radius, width: knobDiameter, height: knobDiameter)
        children[2].place(in: knob, proposal: ProposedSize(knob.size), context: context, into: &list)
    }
}
