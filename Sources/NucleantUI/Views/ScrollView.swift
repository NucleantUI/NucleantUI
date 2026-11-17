//
//  ScrollView.swift
//  NucleantUI
//

/// A scrollable container. The content is measured unconstrained along the
/// scroll axes, then drawn shifted by the current offset and clipped to the
/// scroll view's own bounds.
///
/// Dragged with a finger, the content follows it past either end by less
/// and less and springs back when let go; flung, it carries on and slows
/// down, bouncing off an end it reaches. A wheel or a trackpad moves it as
/// the platform says, inside its ends. Where it is and how it moves is kept
/// in a `Scroller` of its own (Scroll/Scroller.swift): scrolling places the
/// content again and rebuilds nothing.
@View
public struct ScrollView<Content: View> {
    public let axes: Axis.Set
    public let content: Content

    @State private var scroller = Scroller()

    public init(_ axes: Axis.Set = .vertical, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }
}

extension ScrollView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        var inner = context
        // The content is not in a stack of its own; clear any inherited axis so
        // a `Spacer` inside doesn't stretch along the enclosing stack's.
        inner.stackAxis = nil
        let child = inner.child(0) { ctx in buildNode(content, &ctx) }
        // A scroll position the app wrote is taken now, so it is gone to
        // once this pass has placed the content.
        let environment = context.environment
        let animation = context.transaction.disablesAnimations ? nil : context.transaction.animation
        let position = environment.scrollPosition
        if let position {
            scroller.follow(position.position.wrappedValue, anchor: position.anchor, animation: animation)
        }
        let positionID = environment.scrollPositionID
        positionID?.follow(scroller, animation)
        return ContentNode(
            content: ScrollContent(
                axes: axes,
                scroller: scroller,
                targetBehavior: environment.scrollTargetBehavior,
                position: position,
                positionID: positionID,
                effects: context.effects,
                environment: environment
            ),
            children: [child]
        )
    }
}

struct ScrollContent: NodeContent {
    let axes: Axis.Set
    let scroller: Scroller
    /// Where a scroll may come to rest (`.scrollTargetBehavior`), and the
    /// environment the behavior is asked in.
    let targetBehavior: ScrollTargetBehaviorEntry?
    /// The bindings `.scrollPosition` hands it, told where the user scrolls
    /// it once each pass is placed.
    let position: ScrollPositionEntry?
    let positionID: ScrollPositionIDEntry?
    let effects: EffectQueue
    let environment: EnvironmentValues

    /// A scroll view takes whatever it is offered — it is the clip, not the
    /// content, that decides its size.
    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }

        // Unconstrained along each scrollable axis: that is what lets the
        // content be taller than the viewport.
        var contentProposal = ProposedSize(rect.size)
        if axes.contains(.vertical) { contentProposal.height = nil }
        if axes.contains(.horizontal) { contentProposal.width = nil }

        let size = child.sizeThatFits(contentProposal)

        // Where the content is at this frame's time. Still moving on its
        // own, it is placed again next frame.
        scroller.axes = axes
        scroller.targetBehavior = targetBehavior
        scroller.environment = environment
        let store = AnimationStore.current
        let offset: Point
        if context.freezesMotion {
            offset = scroller.offset
        } else {
            offset = scroller.place(viewport: rect.size, contentSize: size, at: store?.now ?? Scroller.now)
            if scroller.isMoving { store?.requestFrame() }
        }

        // The visible rect is the scroll view's own space: `.scrollView`, and
        // `.scrollView(axis:)` for each axis it scrolls along.
        var inner = context.clipped(to: rect)
        for name in [ScrollViewSpaceName(axis: nil)]
            + (axes.contains(.horizontal) ? [ScrollViewSpaceName(axis: .horizontal)] : [])
            + (axes.contains(.vertical) ? [ScrollViewSpaceName(axis: .vertical)] : []) {
            inner.coordinateSpaces.append(CoordinateSpaceFrame(name: name, rect: rect, transform: context.transform))
        }

        // A scroll target layout inside reports its views to this one.
        let contentRect = Rect(
            x: rect.minX - offset.x,
            y: rect.minY - offset.y,
            width: axes.contains(.horizontal) ? size.width : rect.width,
            height: axes.contains(.vertical) ? size.height : rect.height
        )
        if !context.freezesMotion {
            inner.enclosingScroller = scroller
            scroller.beginPlacingContent(at: contentRect.origin)
        }
        child.place(in: contentRect, proposal: contentProposal, context: inner, into: &list)
        // Resized, it may have been moved to where its target behavior
        // rests: shown there next frame.
        if !context.freezesMotion, scroller.endPlacingContent(node: node, at: store?.now ?? Scroller.now) {
            store?.requestFrame()
        }
        // Where the user has scrolled it, for the scroll position bindings.
        if !context.freezesMotion, scroller.userScrolled {
            if let position, let next = scroller.reportedPosition(anchor: position.anchor) {
                let binding = position.position
                effects.afterPass { binding.wrappedValue = next }
            }
            positionID?.report(scroller, effects)
            scroller.noteUserScrollReported()
        }
    }

    var clipsChildren: Bool { true }

    var hitTarget: HitTarget? {
        // Scroll only — a scroll view swallows no taps, so its children keep
        // receiving them (hit testing tries children first regardless).
        HitTarget(scroller: scroller, axes: axes) { [scroller] delta in
            scroller.wheel(by: delta, at: Scroller.now)
        }
    }
}
