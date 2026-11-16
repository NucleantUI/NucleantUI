//
//  Scroller.swift
//  NucleantUI
//
//  What one `ScrollView` knows about where it is and how it moves: its
//  offset, the finger dragging it, the motion it is in once let go, and the
//  phase all of that adds up to. Kept on the scroll view's position (its
//  `@State`), so it outlives every rebuild of the view.
//
//  Nothing here writes view state. Input moves the offset and asks for a
//  placement pass; the scroll view, placing its content, asks for the
//  offset at the frame's time — and for another frame while it is still on
//  its way. Scrolling rebuilds nothing.
//
//  The offset is SwiftUI's content offset: the point of the content shown
//  at the scroll view's top-leading corner. It rests between zero and the
//  content's size less the viewport's, and goes past either end only while
//  a finger drags it there (by less and less: the rubber band) or while it
//  bounces back.
//

import Dispatch

@MainActor
final class Scroller {

    /// The axes it scrolls along; the other is held at zero.
    var axes: Axis.Set = .vertical

    /// Whether it may be dragged past an edge, and bounce back, along each
    /// axis. Set as it is placed.
    var bouncesHorizontally = true
    var bouncesVertically = true

    /// The size it shows the content in, and the content's size, as last
    /// placed.
    private(set) var viewport: Size = .zero
    private(set) var contentSize: Size = .zero

    /// Where it is, as last sampled: the point of the content at the
    /// top-leading corner of the viewport.
    private(set) var offset: Point = .zero

    private(set) var phase: ScrollPhase = .idle

    /// While a finger drags it: where the finger puts the content with no
    /// rubber band. `offset` is this with the part past an edge banded.
    private var dragOffset: Point?

    /// Where it was under the finger, and when, for its speed on release.
    private var tracker = ScrollVelocityTracker()

    /// Its motion along each axis once let go; `nil` along one at rest.
    private var horizontalMotion: ScrollAxisMotion?
    private var verticalMotion: ScrollAxisMotion?

    /// Bumped by every wheel event, so the one that comes last can tell,
    /// once the wheel has been still for a moment, that the scroll is over.
    private var wheelGeneration = 0

    /// How long a wheel has to be still for its scroll to be over.
    static let wheelIdleDelay = 0.15

    /// Whether it is moving on its own: slowing down or springing back.
    var isMoving: Bool { horizontalMotion != nil || verticalMotion != nil }

    /// Whether a finger is dragging it.
    var isDragging: Bool { dragOffset != nil }

    /// The offsets it can rest at along each axis.
    var horizontalBounds: ClosedRange<Double> {
        0...max(0, contentSize.width - viewport.width)
    }

    var verticalBounds: ClosedRange<Double> {
        0...max(0, contentSize.height - viewport.height)
    }

    /// The clock the frames are stamped with (`AnimationStore.now`), read
    /// for an input event between frames.
    static var now: Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    // MARK: - Placement

    /// Placed in `viewport` with content of `contentSize`, at `time`: where
    /// the content is now.
    func place(viewport: Size, contentSize: Size, at time: Double) -> Point {
        self.viewport = viewport
        self.contentSize = contentSize
        if let dragOffset {
            offset = banded(dragOffset)
        } else if isMoving {
            advance(to: time)
        } else {
            // At rest, it rests inside: content that shrank, or a viewport
            // that grew, takes it back to the edge.
            offset = clamped(offset)
        }
        return offset
    }

    /// Sample both motions at `time`, ending the ones that are over.
    private func advance(to time: Double) {
        if var motion = horizontalMotion {
            let sample = motion.sample(at: time, bounds: horizontalBounds)
            offset.x = sample.position
            horizontalMotion = sample.isFinished ? nil : motion
        }
        if var motion = verticalMotion {
            let sample = motion.sample(at: time, bounds: verticalBounds)
            offset.y = sample.position
            verticalMotion = sample.isFinished ? nil : motion
        }
        if !isMoving, phase == .decelerating || phase == .animating {
            offset = clamped(offset)
            phase = .idle
        }
    }

    // MARK: - A finger

    /// A finger came down on it. Moving on its own, it stops where it is —
    /// and the press is the scroll view's, not a tap on what is under it:
    /// true then.
    @discardableResult
    func catchMotion(at time: Double) -> Bool {
        guard isMoving else { return false }
        advance(to: time)
        horizontalMotion = nil
        verticalMotion = nil
        phase = .interacting
        beginDrag(at: time)
        return true
    }

    /// The finger has moved far enough to be scrolling.
    func beginDrag(at time: Double) {
        horizontalMotion = nil
        verticalMotion = nil
        wheelGeneration += 1
        // Caught past an edge, the finger takes it from where it shows: as
        // far past as the rubber band would have dragged it there.
        let unbanded = Point(
            x: unbanded(offset.x, bounds: horizontalBounds, dimension: viewport.width),
            y: unbanded(offset.y, bounds: verticalBounds, dimension: viewport.height)
        )
        dragOffset = unbanded
        phase = .interacting
        tracker.reset()
        tracker.add(offset, at: time)
    }

    /// The finger moved by `delta`; the content goes with it.
    func drag(by delta: Point, at time: Double) {
        guard var dragged = dragOffset else { return }
        if axes.contains(.horizontal) { dragged.x -= delta.x }
        if axes.contains(.vertical) { dragged.y -= delta.y }
        dragOffset = dragged
        offset = banded(dragged)
        tracker.add(offset, at: time)
        Invalidator.shared.requestPlacement()
    }

    /// The finger lifted (or was taken away): it carries on at the speed it
    /// was going, and comes back from past an edge.
    func endDrag(at time: Double) {
        guard dragOffset != nil else { return }
        dragOffset = nil
        let limit = ScrollPhysics.maximumReleaseSpeed
        let sampled = tracker.velocity(at: time)
        let velocity = Point(x: min(max(sampled.x, -limit), limit), y: min(max(sampled.y, -limit), limit))
        tracker.reset()
        if axes.contains(.horizontal) {
            horizontalMotion = .released(
                at: offset.x, velocity: velocity.x, bounds: horizontalBounds,
                time: time, bounces: bouncesHorizontally
            )
        }
        if axes.contains(.vertical) {
            verticalMotion = .released(
                at: offset.y, velocity: velocity.y, bounds: verticalBounds,
                time: time, bounces: bouncesVertically
            )
        }
        phase = isMoving ? .decelerating : .idle
        Invalidator.shared.requestPlacement()
    }

    // MARK: - A wheel or a trackpad

    /// A wheel turned, or two fingers moved on a trackpad, by `delta`. The
    /// platform moves the content itself, momentum included, so it goes
    /// where it is told, inside its edges.
    func wheel(by delta: Point, at time: Double) {
        if isMoving {
            advance(to: time)
            horizontalMotion = nil
            verticalMotion = nil
        }
        var next = offset
        if axes.contains(.horizontal) { next.x -= delta.x }
        if axes.contains(.vertical) { next.y -= delta.y }
        next = clamped(next)
        wheelGeneration += 1
        let generation = wheelGeneration
        let moved = next != offset
        offset = next
        if moved || phase != .idle {
            phase = .interacting
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.wheelIdleDelay) { [weak self] in
                MainActor.assumeIsolated { self?.wheelStopped(generation) }
            }
        }
        if moved { Invalidator.shared.requestPlacement() }
    }

    /// No wheel event since `generation`'s: the scroll is over.
    private func wheelStopped(_ generation: Int) {
        guard generation == wheelGeneration, dragOffset == nil, !isMoving else { return }
        guard phase == .interacting else { return }
        phase = .idle
        Invalidator.shared.requestPlacement()
    }

    // MARK: - Edges

    /// `point` held inside the edges along each axis it scrolls, at zero
    /// along one it does not.
    func clamped(_ point: Point) -> Point {
        Point(
            x: axes.contains(.horizontal) ? min(max(point.x, horizontalBounds.lowerBound), horizontalBounds.upperBound) : 0,
            y: axes.contains(.vertical) ? min(max(point.y, verticalBounds.lowerBound), verticalBounds.upperBound) : 0
        )
    }

    /// Where content dragged to `point` shows: inside the edges as it is,
    /// past one by the rubber band — or held at it along an axis that does
    /// not bounce.
    private func banded(_ point: Point) -> Point {
        Point(
            x: axes.contains(.horizontal)
                ? banded(point.x, bounds: horizontalBounds, dimension: viewport.width, bounces: bouncesHorizontally)
                : 0,
            y: axes.contains(.vertical)
                ? banded(point.y, bounds: verticalBounds, dimension: viewport.height, bounces: bouncesVertically)
                : 0
        )
    }

    private func banded(_ value: Double, bounds: ClosedRange<Double>, dimension: Double, bounces: Bool) -> Double {
        if value < bounds.lowerBound {
            guard bounces else { return bounds.lowerBound }
            return bounds.lowerBound + ScrollPhysics.rubberBand(value - bounds.lowerBound, dimension: dimension)
        }
        if value > bounds.upperBound {
            guard bounces else { return bounds.upperBound }
            return bounds.upperBound + ScrollPhysics.rubberBand(value - bounds.upperBound, dimension: dimension)
        }
        return value
    }

    private func unbanded(_ value: Double, bounds: ClosedRange<Double>, dimension: Double) -> Double {
        if value < bounds.lowerBound {
            return bounds.lowerBound + ScrollPhysics.dragDistance(showing: value - bounds.lowerBound, dimension: dimension)
        }
        if value > bounds.upperBound {
            return bounds.upperBound + ScrollPhysics.dragDistance(showing: value - bounds.upperBound, dimension: dimension)
        }
        return value
    }
}
