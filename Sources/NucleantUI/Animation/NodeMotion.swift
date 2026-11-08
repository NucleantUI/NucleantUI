//
//  NodeMotion.swift
//  NucleantUI
//
//  Animation at the level of placed nodes.
//
//  Geometry: every node remembers the rect layout last gave it. When an
//  animated commit pass gives it a different one, it starts a
//  *displacement* — how far the new rect is from where the node was
//  showing — and each pass shows it at the rect layout gives *now* plus
//  that displacement, shrinking to nothing. Additive, so it converges on
//  whatever layout says even if that moves again mid-way.
//
//  What moves on screen is the leaves — shapes, colors, text, images —
//  each from its own old rect to its own new one, all on one curve.
//  A container is laid out at the new layout at once, and only its
//  *frame* (what hit testing and a clip see) is shown in between: were its
//  children laid out inside an in-between box, they would be squeezed
//  into a layout that is neither the old one nor the new one — a row of
//  buttons wrapping their labels — and a child would ride along with its
//  parent's motion on top of its own.
//
//  A leaf that fills its box (a shape, a color) is drawn at the sizes in
//  between; text keeps its new size and only its center travels, since it
//  would otherwise reflow at every frame.
//
//  Transitions are not motion of this kind: a view arriving or leaving has
//  its transition's body built around it, and the body's modifiers animate
//  their own values (Transition/TransitionSlots.swift).
//

/// A node's animation in flight, carried over when its view is rebuilt.
struct NodeMotion {
    struct Displacement {
        /// How far the center is from where layout puts it, and — for a
        /// node that animates its size — how much bigger it is.
        var dx: Double, dy: Double, dw: Double, dh: Double
        let run: AnimationRun

        /// What is left of it at `now`, and whether it has run out.
        @MainActor func remaining(at now: Double) -> (fraction: Double, isFinished: Bool) {
            let progress = run.progress(at: now)
            return (1 - progress.fraction, progress.isFinished)
        }
    }

    var displacement: Displacement?
}

extension ViewNode {

    /// Given the rect layout chose, the node's frame as shown now and the
    /// rect its content is placed in — the same for a leaf, the layout's
    /// own for a container (see the file comment).
    func animate(
        _ target: Rect,
        context: inout DrawContext,
        store: AnimationStore
    ) -> (frame: Rect, content: Rect) {
        defer { layoutRect = target }

        if store.isCommitPass, let animation = context.animation, let last = layoutRect, last != target {
            let shown = displaced(last, at: store.now)
            let resizes = content.animatesSize
            let displacement = NodeMotion.Displacement(
                dx: shown.midX - target.midX,
                dy: shown.midY - target.midY,
                dw: resizes ? shown.width - target.width : 0,
                dh: resizes ? shown.height - target.height : 0,
                run: AnimationRun(animation, start: store.now)
            )
            let isStill = abs(displacement.dx) < 0.01 && abs(displacement.dy) < 0.01
                && abs(displacement.dw) < 0.01 && abs(displacement.dh) < 0.01
            motion.displacement = isStill ? nil : displacement
            if !isStill { store.noteStarted(displacement.run) }
        }

        var frame = target
        if let displacement = motion.displacement {
            let remaining = displacement.remaining(at: store.now)
            if remaining.isFinished {
                motion.displacement = nil
            } else {
                frame = displaced(target, at: store.now)
                store.requestFrame()
            }
        }
        return (frame, children.isEmpty ? frame : target)
    }

    /// `rect` moved by whatever is left of the displacement at `now`.
    private func displaced(_ rect: Rect, at now: Double) -> Rect {
        guard let displacement = motion.displacement else { return rect }
        let remaining = displacement.remaining(at: now)
        guard !remaining.isFinished else { return rect }
        let k = remaining.fraction
        let width = max(0, rect.width + displacement.dw * k)
        let height = max(0, rect.height + displacement.dh * k)
        return Rect(
            x: rect.midX + displacement.dx * k - width / 2,
            y: rect.midY + displacement.dy * k - height / 2,
            width: width,
            height: height
        )
    }


    /// Take over a rebuilt predecessor's motion: where it last stood and
    /// what it was in the middle of.
    ///
    /// Not into a group: a group is never a box of its own, and one that
    /// replaces a view (an `if` whose other branch is still exiting) would
    /// otherwise slide its new contents over from where the old stood.
    func inheritMotion(from old: ViewNode) {
        guard layoutRect == nil, !content.isTransparent else { return }
        layoutRect = old.layoutRect
        motion = old.motion
    }
}
