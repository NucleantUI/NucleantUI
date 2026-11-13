//
//  HitTesting.swift
//  NucleantUI
//

/// A node that responds to pointer input. Coordinates handed to the callbacks
/// are in the node's own space — the placed frame's origin subtracted and any
/// ambient transform undone.
@MainActor
public final class HitTarget {
    let isEnabled: Bool
    let onPress: (@MainActor (Point) -> Void)?
    /// `(point, inside)` — `inside` is false when the pointer was released
    /// outside the node, which is how a drag-off cancels a button.
    let onRelease: (@MainActor (Point, Bool) -> Void)?
    let onTap: (@MainActor (Point) -> Void)?
    let onScroll: (@MainActor (Point) -> Void)?

    /// How far the pointer must travel before a drag starts reporting.
    let minimumDragDistance: Double
    let onDragChanged: (@MainActor (DragGesture.Value) -> Void)?
    let onDragEnded: (@MainActor (DragGesture.Value) -> Void)?

    public init(
        isEnabled: Bool = true,
        minimumDragDistance: Double = 0,
        onPress: (@MainActor (Point) -> Void)? = nil,
        onRelease: (@MainActor (Point, Bool) -> Void)? = nil,
        onTap: (@MainActor (Point) -> Void)? = nil,
        onScroll: (@MainActor (Point) -> Void)? = nil,
        onDragChanged: (@MainActor (DragGesture.Value) -> Void)? = nil,
        onDragEnded: (@MainActor (DragGesture.Value) -> Void)? = nil
    ) {
        self.isEnabled = isEnabled
        self.minimumDragDistance = minimumDragDistance
        self.onPress = onPress
        self.onRelease = onRelease
        self.onTap = onTap
        self.onScroll = onScroll
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    var handlesPointer: Bool {
        onPress != nil || onRelease != nil || onTap != nil
            || onDragChanged != nil || onDragEnded != nil
    }
    var handlesScroll: Bool { onScroll != nil }
    /// A view that wants drag reports keeps a moving finger; one that only
    /// wants taps yields it to a scroll view around it.
    var takesDrags: Bool { onDragChanged != nil || onDragEnded != nil }
}

/// One node found under a point, with the point already mapped into its space.
/// `value` is whatever the walk was looking for — a `HitTarget`, a
/// `DragSource`, a `DropTarget`.
@MainActor
struct Hit<Value> {
    let value: Value
    let node: ViewNode
    let localPoint: Point
    /// The node's frame, kept so a later release can ask "still inside?".
    let frame: Rect
    let transform: Transform
}

typealias HitResult = Hit<HitTarget>

extension Hit where Value == HitTarget {
    var target: HitTarget { value }
}

extension ViewNode {

    /// The frontmost node under `point` (window coordinates) whose target
    /// satisfies `matching`.
    func hitTest(_ point: Point, matching: (HitTarget) -> Bool) -> HitResult? {
        hitTest(point, lookingFor: .hitTarget) { node in
            guard let target = node.content.hitTarget, target.isEnabled, matching(target) else {
                return nil
            }
            return target
        }
    }

    /// The frontmost node under `point` for which `select` answers — the
    /// one walk behind every kind of hit test.
    ///
    /// Depth-first with children reversed: the display list paints children in
    /// order, so the last one drawn is on top and must be tested first.
    ///
    /// `wanted` is what a node `select` answers for has — a hover target, a
    /// drop target. A subtree with none of it is passed over at once, and
    /// `select` is asked only of a node with some; empty, every node is
    /// asked.
    func hitTest<Value>(_ point: Point, lookingFor wanted: NodeTraits = [], select: (ViewNode) -> Value?) -> Hit<Value>? {
        if !wanted.isEmpty, subtreeTraits.isDisjoint(with: wanted) { return nil }
        // Off screen, whatever the frames left over from an earlier pass say
        // — or on its way out, drawn but no longer there.
        guard !traits.contains(.parked), removal == nil else { return nil }
        // `.allowsHitTesting(false)`: nothing here can be hit.
        guard !traits.contains(.blocksHitTesting) else { return nil }
        // A clipping node's children only exist inside its frame.
        if traits.contains(.clipsChildren) {
            guard let local = mapIntoLocalSpace(point), frame.contains(local) else { return nil }
        }
        // Nor, under a `.contentShape`, outside the shape.
        if traits.contains(.hitShape), let shape = content.hitShape {
            guard let local = mapIntoLocalSpace(point), shape.contains(local, in: frame) else { return nil }
        }
        for child in (contentHitTestOrder() ?? children).reversed() {
            if let hit = child.hitTest(point, lookingFor: wanted, select: select) { return hit }
        }

        if !wanted.isEmpty, traits.isDisjoint(with: wanted) { return nil }
        guard let value = select(self) else { return nil }
        // Where its content is drawn, through any effect between the two.
        let drawn = contentTransform
        guard let local = drawn.inverseApplied(to: point), frame.contains(local) else { return nil }
        guard wrappedContentAccepts(point) else { return nil }
        return Hit(
            value: value,
            node: self,
            localPoint: Point(x: local.x - frame.minX, y: local.y - frame.minY),
            frame: frame,
            transform: drawn
        )
    }

    /// The transform this node's content is drawn under: the one at the end
    /// of the run of single children below it.
    ///
    /// An effect in that run (`.offset`, `.scaleEffect`, `.rotationEffect`,
    /// a transition's move) moves what is drawn without moving this node's
    /// frame. A gesture attached after one is on the moved view, as in
    /// SwiftUI, so it is hit where the view is drawn, not where layout put
    /// it. Layout alone (`.frame`, `.padding`, a `ScrollView`) places by
    /// rect and never changes a transform, so with no effect in the run this
    /// is the node's own.
    var contentTransform: Transform {
        var probe = self
        while true {
            let inner = probe.layoutChildren
            guard inner.count == 1 else { return probe.transform }
            probe = inner[0]
        }
    }

    /// Whether what this node wraps takes a hit at `point` — false when a
    /// `.contentShape` below it leaves the point outside, or an
    /// `.allowsHitTesting(false)` turns it off. Only the run of single-child
    /// nodes is looked at: `Circle().contentShape(Circle()).onTapGesture`
    /// is the tap's own content, a stack's children are not.
    func wrappedContentAccepts(_ point: Point) -> Bool {
        var probe = self
        while true {
            let inner = probe.layoutChildren
            guard inner.count == 1 else { return true }
            probe = inner[0]
            if probe.traits.contains(.blocksHitTesting) { return false }
            if probe.traits.contains(.hitShape), let shape = probe.content.hitShape {
                guard let local = probe.mapIntoLocalSpace(point) else { return false }
                return shape.contains(local, in: probe.frame)
            }
        }
    }

    /// `point` with this node's ambient transform undone — `nil` for a
    /// degenerate transform (a zero `scaleEffect`), which can't be hit.
    func mapIntoLocalSpace(_ point: Point) -> Point? {
        transform.inverseApplied(to: point)
    }

    /// Whether `point` still falls inside this node — asked on pointer release
    /// to decide whether a press became a tap.
    func contains(windowPoint point: Point) -> Bool {
        guard let local = mapIntoLocalSpace(point) else { return false }
        return frame.contains(local)
    }
}

extension Hit {
    /// The window point mapped into this result's node space, for a later
    /// event in the same gesture.
    func localPoint(for windowPoint: Point) -> Point? {
        guard let local = transform.inverseApplied(to: windowPoint) else { return nil }
        return Point(x: local.x - frame.minX, y: local.y - frame.minY)
    }

    func contains(_ windowPoint: Point) -> Bool {
        guard let local = transform.inverseApplied(to: windowPoint) else { return false }
        return frame.contains(local)
    }
}

extension Transform {
    /// `point` with this transform undone: `nil` for a degenerate transform
    /// (a zero `scaleEffect`), which can't be hit.
    ///
    /// A move alone — an `.offset`, a scroll position, the common case — is
    /// undone by taking it away, with no inverse to work out.
    func inverseApplied(to point: Point) -> Point? {
        if e11 == 1, e12 == 0, e21 == 0, e22 == 1 {
            return Point(x: point.x - e13, y: point.y - e23)
        }
        return inverted()?.apply(to: point)
    }
}
