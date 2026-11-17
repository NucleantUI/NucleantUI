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
    /// axis (`.scrollBounceBehavior`). Set as it is placed.
    var horizontalBounce = ScrollBounceBehavior.automatic
    var verticalBounce = ScrollBounceBehavior.automatic

    /// Whether it bounces along each axis, for its content as last placed.
    var bouncesHorizontally: Bool {
        horizontalBounce.bounces(contentIsLonger: horizontalBounds.upperBound > horizontalBounds.lowerBound)
    }

    var bouncesVertically: Bool {
        verticalBounce.bounces(contentIsLonger: verticalBounds.upperBound > verticalBounds.lowerBound)
    }

    /// Whether a finger or a wheel can move it along `axis`: one it scrolls,
    /// with content longer than it there or bouncing even so.
    func moves(along axis: Axis) -> Bool {
        switch axis {
        case .horizontal:
            axes.contains(.horizontal) && (horizontalBounds.upperBound > horizontalBounds.lowerBound || bouncesHorizontally)
        case .vertical:
            axes.contains(.vertical) && (verticalBounds.upperBound > verticalBounds.lowerBound || bouncesVertically)
        }
    }

    /// Whether it moves to keep the content in place as sizes change, in
    /// the pass being placed (`Transaction.scrollContentOffsetAdjustmentBehavior`).
    /// Set as it is placed.
    var adjustsContentOffset = true

    /// What a finger scrolling it does to the on-screen keyboard
    /// (`.scrollDismissesKeyboard`). Set as it is placed.
    var keyboardDismissal = ScrollDismissesKeyboardMode.automatic

    /// Whether a finger scrolling it puts the keyboard away now: as the
    /// drag begins, or — `onRelease` — as it lets go, moving the content
    /// down toward the keyboard.
    func dismissesKeyboard(onRelease: Bool) -> Bool {
        switch keyboardDismissal.kind {
        case .automatic, .immediately:
            return !onRelease
        case .interactively:
            guard onRelease, axes.contains(.vertical), let velocity = releaseVelocity else { return false }
            return velocity.dy < 0
        case .never:
            return false
        }
    }

    /// The size it shows the content in, and the content's size, as last
    /// placed.
    private(set) var viewport: Size = .zero
    private(set) var contentSize: Size = .zero

    /// What the content is inset by — content margins and safe area
    /// padding — as last placed. It rests that far in from the scroll
    /// view's edges, and scrolls past them.
    private(set) var insets = EdgeInsets()

    /// Where it is, as last sampled: the point of the content at the
    /// top-leading corner of the viewport — before zero by the leading
    /// insets at the start.
    private(set) var offset: Point = .zero

    /// The `.defaultScrollAnchor` points it starts at and keeps to as sizes
    /// change. Set as it is placed.
    var initialAnchor: UnitPoint?
    var sizeChangeAnchor: UnitPoint?

    /// Whether it has been placed — the first time, it starts at its
    /// initial anchor.
    private var hasBeenPlaced = false

    private(set) var phase: ScrollPhase = .idle {
        didSet {
            guard phase != oldValue else { return }
            phaseChanges.append(PhaseChange(
                old: oldValue,
                new: phase,
                velocity: phase == .decelerating ? releaseVelocity : nil
            ))
            // Placed again, the scroll view hands the change on.
            Invalidator.shared.requestPlacement()
        }
    }

    /// One change of phase, and — into `decelerating` — the speed the
    /// finger let go at.
    struct PhaseChange: Equatable {
        let old: ScrollPhase
        let new: ScrollPhase
        let velocity: Vector?
    }

    /// The phases it went through since the scroll view last took them:
    /// a phase can come and go between two frames.
    private(set) var phaseChanges: [PhaseChange] = []

    /// How fast the finger let it go, for the change into `decelerating`.
    private var releaseVelocity: Vector?

    /// The phase changes since the last time, emptied.
    func takePhaseChanges() -> [PhaseChange] {
        defer { phaseChanges.removeAll(keepingCapacity: true) }
        return phaseChanges
    }

    /// A finger came down on it: it may be about to scroll.
    func beginTracking() {
        if phase == .idle { phase = .tracking }
    }

    /// The finger it was tracking lifted without scrolling it, or went to
    /// another scroll view.
    func endTracking() {
        if phase == .tracking { phase = .idle }
    }

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

    /// The views of its scroll target layout as last placed — their nodes,
    /// and their frames in the content's own space — and those reported so
    /// far in the pass under way, with where the content's origin is in it.
    private(set) var targetNodes: [ViewNode] = []
    private(set) var targetFrames: [Rect] = []
    private var placingTargets: (nodes: [ViewNode], frames: [Rect])?
    private var contentOrigin: Point = .zero

    /// Moved by the user since where it is was last reported to a scroll
    /// position binding.
    private(set) var userScrolled = false

    /// An edge a scroll position put it at, which it keeps to as the
    /// content changes size — until the user scrolls it, or the app moves
    /// it somewhere else.
    private var pinnedEdge: Edge?

    /// The `ScrollPosition` it was last given or reported, so a binding
    /// handing it back is not taken for a new one — and the same for the id
    /// of `.scrollPosition(id:)`.
    var lastPosition: ScrollPosition?
    var lastPositionID: AnyHashable?

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
        /// Passes in a row it was worked out exactly to `last`.
        var stable = 0

        /// Passes it is worked out again for, at most.
        static let maximumPasses = 60

        /// Passes in a row an exact answer has to hold for it to be done: a
        /// lazy container may build and measure around what was found
        /// for a frame or two after it is reached, moving it.
        static let stablePasses = 5
    }

    /// Whether a scroll the app asked for is still being worked out — the
    /// scroll view is placed again each frame until it is.
    var hasPendingRequest: Bool { request != nil }

    /// Whether it is moving on its own: slowing down, springing back, or
    /// on its way where the app asked.
    var isMoving: Bool { horizontalMotion != nil || verticalMotion != nil || programmatic != nil }

    /// Whether a finger is dragging it.
    var isDragging: Bool { dragOffset != nil }

    /// The offsets it can rest at along each axis: from the leading inset
    /// before the content's start to the trailing inset past its end.
    var horizontalBounds: ClosedRange<Double> {
        let start = -insets.leading
        return start...max(start, contentSize.width + insets.trailing - viewport.width)
    }

    var verticalBounds: ClosedRange<Double> {
        let start = -insets.top
        return start...max(start, contentSize.height + insets.bottom - viewport.height)
    }

    /// The viewport inside the insets — what the content is shown in, and
    /// where in the viewport that starts.
    var container: Size {
        Size(width: max(0, viewport.width - insets.horizontal), height: max(0, viewport.height - insets.vertical))
    }

    var containerOrigin: Point {
        Point(x: insets.leading, y: insets.top)
    }

    /// The clock the frames are stamped with (`AnimationStore.now`), read
    /// for an input event between frames.
    static var now: Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    // MARK: - Placement

    /// Placed in `viewport` with content of `contentSize`, at `time`: where
    /// the content is now.
    func place(viewport: Size, contentSize: Size, insets: EdgeInsets = EdgeInsets(), at time: Double) -> Point {
        if targetBehavior != nil, self.viewport != .zero, viewport != self.viewport, resizedFrom == nil {
            resizedFrom = (offset, self.viewport)
        }
        let before = (horizontal: horizontalBounds, vertical: verticalBounds)
        self.viewport = viewport
        self.contentSize = contentSize
        self.insets = insets
        guard hasBeenPlaced else {
            hasBeenPlaced = true
            offset = startingOffset()
            return offset
        }
        if let dragOffset {
            offset = banded(dragOffset)
        } else if isMoving {
            advance(to: time)
        } else {
            // At rest, it keeps its place as the sizes change — unless the
            // change asked it to stay where it is — and rests inside:
            // content that shrank, or a viewport that grew, takes it back to
            // the edge.
            if request == nil, adjustsContentOffset { offset = keptPlace(from: before) }
            offset = clamped(offset)
        }
        return offset
    }

    /// Where it starts: the initial anchor's point of the range it can rest
    /// in — the start, without one.
    private func startingOffset() -> Point {
        let anchor = initialAnchor ?? .topLeading
        let horizontal = horizontalBounds
        let vertical = verticalBounds
        return clamped(Point(
            x: horizontal.lowerBound + anchor.x * (horizontal.upperBound - horizontal.lowerBound),
            y: vertical.lowerBound + anchor.y * (vertical.upperBound - vertical.lowerBound)
        ))
    }

    /// Where it is after the range it can rest in moved from `before`: as
    /// far from the size-change anchor's point of the range as it was — from
    /// the start, without one.
    private func keptPlace(from before: (horizontal: ClosedRange<Double>, vertical: ClosedRange<Double>)) -> Point {
        let anchor = sizeChangeAnchor ?? .topLeading
        func kept(_ value: Double, _ old: ClosedRange<Double>, _ new: ClosedRange<Double>, _ fraction: Double) -> Double {
            value + (new.lowerBound - old.lowerBound) * (1 - fraction) + (new.upperBound - old.upperBound) * fraction
        }
        return Point(
            x: kept(offset.x, before.horizontal, horizontalBounds, anchor.x),
            y: kept(offset.y, before.vertical, verticalBounds, anchor.y)
        )
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
        userScrolled = false
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
        pinnedEdge = nil
        userScrolled = false
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
            // Measured against content placed at an offset part of the way
            // there, the same place comes out a rounding error apart.
            moved = !Self.isSamePlace(target, programmatic?.to ?? offset)
            if moved { retarget(to: target) }
        }
        // Found where it is built, and the same for a few passes: done.
        let same = current.last.map { Self.isSamePlace($0, target) } ?? false
        current.stable = resolved.isExact && same ? current.stable + 1 : 0
        let settled = current.stable >= ScrollRequest.stablePasses
        current.last = target
        request = settled || current.passes >= ScrollRequest.maximumPasses ? nil : current
        return moved
    }

    /// Whether two offsets are the same place, but for rounding.
    private static func isSamePlace(_ a: Point, _ b: Point) -> Bool {
        abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6
    }

    /// The offset that shows `rect`, in the content's own space, in the
    /// container — the viewport inside the insets: its `anchor` point at
    /// the container's same point, or — without one — the least move that
    /// shows all of it.
    func offset(showing rect: Rect, anchor: UnitPoint?) -> Point {
        var target = offset
        for (axis, along) in [(Axis.horizontal, Axis.Set.horizontal), (.vertical, .vertical)] where axes.contains(along) {
            let start = rect.origin[axis]
            let length = rect.size[axis]
            let lead = containerOrigin[axis]
            let visible = container[axis]
            let shown = offset[axis] + lead
            if let anchor {
                let fraction = axis == .horizontal ? anchor.x : anchor.y
                target[axis] = start + fraction * length - fraction * visible - lead
            } else if start < shown || length > visible {
                target[axis] = start - lead
            } else if start + length > shown + visible {
                target[axis] = start + length - visible - lead
            }
        }
        return clamped(target)
    }

    /// The offset that shows the content's `edge`, held where it is along
    /// the other axis.
    func offset(at edge: Edge) -> Point {
        var target = offset
        switch edge {
        case .top: target.y = verticalBounds.lowerBound
        case .bottom: target.y = verticalBounds.upperBound
        case .leading: target.x = horizontalBounds.lowerBound
        case .trailing: target.x = horizontalBounds.upperBound
        }
        return clamped(target)
    }

    /// Go to `edge` once the content is placed, and keep to it as the
    /// content changes size.
    func pin(to edge: Edge, animation: Animation?) {
        request({ scroller, _ in (scroller.offset(at: edge), true) }, animation: animation)
        pinnedEdge = edge
    }

    /// The view of its scroll target layout a scroll position names: with
    /// no anchor the first one in view, else the one under the anchor's
    /// point of the viewport (the nearest, between two).
    func positionedView(anchor: UnitPoint?) -> ViewNode? {
        guard !targetNodes.isEmpty else { return nil }
        let visible = Rect(origin: offset + containerOrigin, size: container)
        guard let anchor else {
            for (index, frame) in targetFrames.enumerated()
            where frame.maxX > visible.minX && frame.minX < visible.maxX
                && frame.maxY > visible.minY && frame.minY < visible.maxY {
                return targetNodes[index]
            }
            return nil
        }
        let point = visible.origin + Point(x: anchor.x * visible.width, y: anchor.y * visible.height)
        var best: (index: Int, distance: Double)?
        for (index, frame) in targetFrames.enumerated() {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best.map { targetNodes[$0.index] }
    }

    /// Reported where it is after the user moved it: the next report waits
    /// for the next move, once it has come to rest.
    func noteUserScrollReported() {
        if phase == .idle { userScrolled = false }
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
        placingTargets = nil
    }

    /// A scroll target layout inside was placed with `views`.
    func addTargets(_ views: [ViewNode]) {
        var placing = placingTargets ?? ([], [])
        for view in views {
            placing.nodes.append(view)
            placing.frames.append(view.frame.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y))
        }
        placingTargets = placing
    }

    /// The content is placed. Resized at rest under a target behavior, it
    /// goes where the behavior says for the new size — true then: placed
    /// again, it shows there.
    func endPlacingContent(node: ViewNode, at time: Double) -> Bool {
        targetNodes = placingTargets?.nodes ?? []
        targetFrames = placingTargets?.frames ?? []
        placingTargets = nil
        if request != nil { return followRequest(node: node, at: time) }
        // Told to stay where it is: no longer at the edge it was pinned to,
        // nor moved where its target behavior rests in a resized viewport.
        if !adjustsContentOffset {
            if let pinnedEdge, offset(at: pinnedEdge) != offset { self.pinnedEdge = nil }
            resizedFrom = nil
            return false
        }
        if let pinnedEdge, !isDragging, !isMoving {
            let pinned = offset(at: pinnedEdge)
            if pinned != offset {
                offset = pinned
                return true
            }
        }
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
        // Targets are rects of the content the container — the viewport
        // inside the insets — shows.
        let lead = containerOrigin
        var target = ScrollTarget(rect: Rect(origin: proposed + lead, size: container))
        let context = ScrollTargetBehaviorContext(
            originalTarget: ScrollTarget(rect: Rect(origin: origin + lead, size: container)),
            velocity: velocity,
            contentSize: contentSize,
            containerSize: container,
            axes: axes,
            environment: environment,
            targetFrames: targetFrames
        )
        behavior.updateTarget(&target, context)
        var resting = target.rect.origin - lead
        // The rect's anchor point at the container's same point.
        if let anchor = target.anchor {
            resting.x += anchor.x * (target.rect.width - container.width)
            resting.y += anchor.y * (target.rect.height - container.height)
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
        pinnedEdge = nil
        userScrolled = true
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
        releaseVelocity = velocity
        // Where it would come to rest, moved where the target behavior says.
        let natural = clamped(Point(
            x: ScrollAxisMotion.projectedEnd(from: offset.x, velocity: velocity.x),
            y: ScrollAxisMotion.projectedEnd(from: offset.y, velocity: velocity.y)
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
        if moved {
            pinnedEdge = nil
            userScrolled = true
        }
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
            return bounds.lowerBound + RubberBand(dimension: dimension).shown(dragged: value - bounds.lowerBound)
        }
        if value > bounds.upperBound {
            guard bounces else { return bounds.upperBound }
            return bounds.upperBound + RubberBand(dimension: dimension).shown(dragged: value - bounds.upperBound)
        }
        return value
    }

    private func unbanded(_ value: Double, bounds: ClosedRange<Double>, dimension: Double) -> Double {
        if value < bounds.lowerBound {
            return bounds.lowerBound + RubberBand(dimension: dimension).dragged(shown: value - bounds.lowerBound)
        }
        if value > bounds.upperBound {
            return bounds.upperBound + RubberBand(dimension: dimension).dragged(shown: value - bounds.upperBound)
        }
        return value
    }
}
