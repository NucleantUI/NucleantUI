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

    /// Where `.scrollTargetBehavior` lets a scroll come to rest, and the
    /// environment it is asked in. Set as it is placed.
    var targetBehavior: ScrollTargetBehaviorEntry?
    var environment = EnvironmentValues()

    /// Where the scroll going on now began — the target a behavior is told
    /// it started from.
    private var gestureOrigin: Point = .zero

    /// The views of its scroll target layout, in the content's own space,
    /// as last placed; and those reported so far in the pass under way,
    /// with where the content's origin is in it.
    private(set) var targetFrames: [Rect] = []
    private var placingTargetFrames: [Rect]?
    private var contentOrigin: Point = .zero

    /// Where it was, and in what viewport, before the viewport last changed
    /// size — until a target behavior has said where to be in the new one.
    private var resizedFrom: (offset: Point, viewport: Size)?

    /// A scroll the app asked for, under way: from where it was to `to`,
    /// along `animation`'s curve, since `start`.
    private var programmatic: (from: Point, to: Point, animation: Animation, start: Double)?

    /// A scroll the app asked for whose destination is worked out from the
    /// content as it is placed — a view by its id, which a lazy container
    /// may not have built yet — and again each pass until it holds still.
    private var request: ScrollRequest?

    struct ScrollRequest {
        /// Where to go, from the scroll view's node as just placed; `nil`
        /// while it cannot be told. Exact once what it scrolls to is built.
        let resolve: @MainActor (Scroller, ViewNode) -> (offset: Point, isExact: Bool)?
        let animation: Animation?
        var started = false
        var last: Point?
        var passes = 0

        /// Passes it is worked out again for, at most.
        static let maximumPasses = 30
    }

    /// Whether it is moving on its own: slowing down, springing back, or
    /// on its way where the app asked.
    var isMoving: Bool { horizontalMotion != nil || verticalMotion != nil || programmatic != nil }

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
        if targetBehavior != nil, self.viewport != .zero, viewport != self.viewport, resizedFrom == nil {
            resizedFrom = (offset, self.viewport)
        }
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
        if let scroll = programmatic {
            let progress = scroll.animation.progress(after: time - scroll.start)
            if progress.isFinished {
                offset = scroll.to
                programmatic = nil
            } else {
                offset = scroll.from + (scroll.to - scroll.from) * progress.fraction
            }
        }
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

    // MARK: - Where the app asks

    /// Go to `target`: at once, or along `animation`'s curve — the
    /// `animating` phase. A custom animation keeps state between frames and
    /// has no curve to sample here, so it goes at once too.
    func scroll(to target: Point, animation: Animation?, at time: Double) {
        if isMoving { advance(to: time) }
        horizontalMotion = nil
        verticalMotion = nil
        programmatic = nil
        dragOffset = nil
        let destination = clamped(target)
        if let animation, destination != offset, animation.progress(after: .infinity).isFinished,
           !animation.progress(after: 0).isFinished {
            programmatic = (offset, destination, animation, time)
            phase = .animating
        } else {
            offset = destination
            phase = .idle
        }
        Invalidator.shared.requestPlacement()
    }

    /// Go where `resolve` says once the content is placed, and keep to it
    /// as what it is worked out from settles.
    func request(
        _ resolve: @escaping @MainActor (Scroller, ViewNode) -> (offset: Point, isExact: Bool)?,
        animation: Animation?
    ) {
        request = ScrollRequest(resolve: resolve, animation: animation)
        Invalidator.shared.requestPlacement()
    }

    /// Where it now has to go, for a scroll on its way somewhere else: an
    /// animated one ends there instead; one at rest goes there.
    private func retarget(to target: Point) {
        let destination = clamped(target)
        if var scroll = programmatic {
            scroll.to = destination
            programmatic = scroll
        } else if !isMoving, !isDragging {
            offset = destination
        }
    }

    /// The request in flight worked out again from the scroll view's node
    /// as just placed — true when that moved it.
    private func followRequest(node: ViewNode, at time: Double) -> Bool {
        guard var current = request else { return false }
        current.passes += 1
        guard let resolved = current.resolve(self, node) else {
            request = current.passes < ScrollRequest.maximumPasses ? current : nil
            return false
        }
        let target = clamped(resolved.offset)
        let moved: Bool
        if !current.started {
            current.started = true
            scroll(to: target, animation: current.animation, at: time)
            moved = true
        } else {
            moved = target != (programmatic?.to ?? offset)
            if moved { retarget(to: target) }
        }
        // Found where it is built, and the same twice: done.
        let settled = resolved.isExact && current.last == target
        current.last = target
        request = settled || current.passes >= ScrollRequest.maximumPasses ? nil : current
        return moved
    }

    /// The offset that shows `rect`, in the content's own space: its
    /// `anchor` point at the viewport's same point, or — without one — the
    /// least move that shows all of it.
    func offset(showing rect: Rect, anchor: UnitPoint?) -> Point {
        var target = offset
        for (axis, along) in [(Axis.horizontal, Axis.Set.horizontal), (.vertical, .vertical)] where axes.contains(along) {
            let start = rect.origin[axis]
            let length = rect.size[axis]
            let visible = viewport[axis]
            if let anchor {
                let fraction = axis == .horizontal ? anchor.x : anchor.y
                target[axis] = start + fraction * length - fraction * visible
            } else if start < offset[axis] || length > visible {
                target[axis] = start
            } else if start + length > offset[axis] + visible {
                target[axis] = start + length - visible
            }
        }
        return clamped(target)
    }

    /// `rect`, a frame placed in this pass's layout space, in the content's
    /// own.
    func contentRect(_ rect: Rect) -> Rect {
        rect.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y)
    }

    // MARK: - Targets

    /// The content is about to be placed with its origin at `origin`, in
    /// the space the target layout reports frames in.
    func beginPlacingContent(at origin: Point) {
        contentOrigin = origin
        placingTargetFrames = nil
    }

    /// A scroll target layout inside was placed with its views at `frames`.
    func addTargetFrames(_ frames: [Rect]) {
        var placing = placingTargetFrames ?? []
        for frame in frames {
            placing.append(frame.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y))
        }
        placingTargetFrames = placing
    }

    /// The content is placed. Resized at rest under a target behavior, it
    /// goes where the behavior says for the new size — true then: placed
    /// again, it shows there.
    func endPlacingContent(node: ViewNode, at time: Double) -> Bool {
        targetFrames = placingTargetFrames ?? []
        placingTargetFrames = nil
        if request != nil { return followRequest(node: node, at: time) }
        guard let resized = resizedFrom else { return false }
        resizedFrom = nil
        guard !isDragging, !isMoving else { return false }
        // Where it was, as far into the new size as into the old.
        var proposed = resized.offset
        for axis in [Axis.horizontal, .vertical] where resized.viewport[axis] > 0 {
            proposed[axis] = resized.offset[axis] * viewport[axis] / resized.viewport[axis]
        }
        guard let target = restingPlace(proposing: clamped(proposed), from: clamped(proposed), velocity: .zero),
              target != offset
        else { return false }
        offset = target
        return true
    }

    /// Where a scroll that would come to rest at `proposed`, having begun
    /// at `origin` and going at `velocity`, rests under the target
    /// behavior; `nil` without one.
    private func restingPlace(proposing proposed: Point, from origin: Point, velocity: Vector) -> Point? {
        guard let behavior = targetBehavior else { return nil }
        var target = ScrollTarget(rect: Rect(origin: proposed, size: viewport))
        let context = ScrollTargetBehaviorContext(
            originalTarget: ScrollTarget(rect: Rect(origin: origin, size: viewport)),
            velocity: velocity,
            contentSize: contentSize,
            containerSize: viewport,
            axes: axes,
            environment: environment,
            targetFrames: targetFrames
        )
        behavior.updateTarget(&target, context)
        var resting = target.rect.origin
        // The rect's anchor point at the viewport's same point.
        if let anchor = target.anchor {
            resting.x += anchor.x * (target.rect.width - viewport.width)
            resting.y += anchor.y * (target.rect.height - viewport.height)
        }
        return clamped(resting)
    }

    /// Spring from where it is, at `velocity`, to rest at `target`.
    private func settle(to target: Point, velocity: Vector, at time: Double) {
        horizontalMotion = axes.contains(.horizontal)
            ? .settling(from: offset.x, velocity: velocity.x, to: target.x, time: time, bounces: bouncesHorizontally)
            : nil
        verticalMotion = axes.contains(.vertical)
            ? .settling(from: offset.y, velocity: velocity.y, to: target.y, time: time, bounces: bouncesVertically)
            : nil
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
        programmatic = nil
        request = nil
        phase = .interacting
        beginDrag(at: time)
        return true
    }

    /// The finger has moved far enough to be scrolling.
    func beginDrag(at time: Double) {
        horizontalMotion = nil
        verticalMotion = nil
        programmatic = nil
        request = nil
        wheelGeneration += 1
        // Caught past an edge, the finger takes it from where it shows: as
        // far past as the rubber band would have dragged it there.
        let unbanded = Point(
            x: unbanded(offset.x, bounds: horizontalBounds, dimension: viewport.width),
            y: unbanded(offset.y, bounds: verticalBounds, dimension: viewport.height)
        )
        dragOffset = unbanded
        gestureOrigin = clamped(offset)
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
        // Where it would come to rest, moved where the target behavior says.
        let natural = clamped(Point(
            x: ScrollPhysics.projectedEnd(from: offset.x, velocity: velocity.x),
            y: ScrollPhysics.projectedEnd(from: offset.y, velocity: velocity.y)
        ))
        if let target = restingPlace(proposing: natural, from: gestureOrigin, velocity: velocity) {
            settle(to: target, velocity: velocity, at: time)
        } else {
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
            programmatic = nil
        }
        request = nil
        // The first event of a wheel scroll is where it began.
        if phase != .interacting { gestureOrigin = offset }
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
        // Under a target behavior, it springs from where the wheel left it
        // to where the behavior lets it rest.
        let time = Self.now
        if let target = restingPlace(proposing: offset, from: gestureOrigin, velocity: .zero), target != offset {
            settle(to: target, velocity: .zero, at: time)
            phase = .decelerating
        } else {
            phase = .idle
        }
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
