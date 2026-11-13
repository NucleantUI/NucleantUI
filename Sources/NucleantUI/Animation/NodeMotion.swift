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
    /// How far the center is from where layout puts it, and — for a node
    /// that animates its size — how much bigger it is: ((dx, dy), (dw, dh)).
    typealias Offset = AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>

    /// What is left of the way to where layout puts the node. A move made
    /// while one is under way turns from where the node is showing, as
    /// fast as it is going (Motion.swift).
    var displacement: Motion<Offset>?

    /// How fast layout moved the node while it moved it without animating
    /// (`Transaction.tracksVelocity`), so a spring that takes over sets off
    /// at that speed: ((x, y), (width, height)) per second.
    var sampler = VelocitySampler<Offset>()
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
            let resizes = !traits.contains(.keepsSizeWhileMoving)
            let offset = NodeMotion.Offset(
                AnimatablePair(last.midX - target.midX, last.midY - target.midY),
                AnimatablePair(resizes ? last.width - target.width : 0, resizes ? last.height - target.height : 0)
            )
            // Moved by next to nothing: what is under way, if anything,
            // carries on.
            let isStill = abs(offset.first.first) < 0.01 && abs(offset.first.second) < 0.01
                && abs(offset.second.first) < 0.01 && abs(offset.second.second) < 0.01
            if !isStill {
                motion.displacement = Motion.begin(
                    offset: offset,
                    previous: motion.displacement,
                    tracked: motion.sampler.velocity(at: store.now),
                    animation: animation,
                    at: store.now
                )
                if let displacement = motion.displacement {
                    store.noteStarted(displacement.run)
                }
            }
            motion.sampler.reset()
        } else if store.isCommitPass, context.animation == nil, let last = layoutRect, last != target {
            // Moved at once: under a drag, note where to, and when.
            if store.transaction.tracksVelocity {
                let resizes = !traits.contains(.keepsSizeWhileMoving)
                motion.sampler.add(NodeMotion.Offset(
                    AnimatablePair(target.midX, target.midY),
                    AnimatablePair(resizes ? target.width : 0, resizes ? target.height : 0)
                ), at: store.now)
            } else {
                motion.sampler.reset()
            }
        }

        var frame = target
        if let displacement = motion.displacement {
            let left = displacement.displacement(at: store.now)
            if left.isFinished {
                motion.displacement = nil
            } else {
                frame = displaced(target, by: left.value)
                store.requestFrame()
            }
        }
        return (frame, children.isEmpty ? frame : target)
    }

    /// `rect` moved by `offset`.
    private func displaced(_ rect: Rect, by offset: NodeMotion.Offset) -> Rect {
        let width = max(0, rect.width + offset.second.first)
        let height = max(0, rect.height + offset.second.second)
        return Rect(
            x: rect.midX + offset.first.first - width / 2,
            y: rect.midY + offset.first.second - height / 2,
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
        guard layoutRect == nil, !isTransparent else { return }
        layoutRect = old.layoutRect
        motion = old.motion
    }
}
