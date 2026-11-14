# Phase 3: layout caches and stack math

Most of this phase is self-contained. Items marked **standalone** need
nothing from the other phases.

## 3.1 A node's caches are dictionaries (standalone)

**Today.** [ViewNode.swift](../../Sources/NucleantUI/Layout/ViewNode.swift)
gives every node three dictionaries:

```swift
private var measurements: [ProposedSize: Size] = [:]
private var flexibilities: [Axis: LayoutPriorityClass] = [:]
var preferenceCache: [ObjectIdentifier: OpaqueValue] = [:]
```

- `measurements` hashes two optional doubles on every `sizeThatFits`, and
  allocates storage on a node's first measurement. At 16 entries it is
  emptied whole.
- `flexibilities` is a dictionary for a key with two possible values.

**Do instead.**

- A fixed inline cache of three or four `(proposal, size)` pairs, searched
  by comparing, with the oldest entry replaced when it is full. No hashing,
  no heap block, and a node that sees many proposals loses one entry at a
  time and not all sixteen.
- Two optional bytes for the flexibilities.
- Leave `preferenceCache` until phase 2, where it can become a field.

Most nodes see one to three proposals in a pass. Check that with the
`measured` count in the perf trace on a deep example before choosing the
size.

## 3.2 A stack measures every child three times

**Today.** `StackContent.fittingOrder` in
[StackContent.swift](../../Sources/NucleantUI/Layout/StackContent.swift)
measures each child with the axis proposed 0 and again with it proposed
infinity, to sort the children by how far they stretch. `layout` then
measures each child a third time with its share. `StackLayoutRun` in
[StackLayouts.swift](../../Sources/NucleantUI/Layout/StackLayouts.swift)
does the same.

The two probe proposals are ones nobody else asks, so each takes a slot in
the child's cache. Under stacks nested on alternating axes, each level
multiplies the distinct proposals reaching the level below, and the caches
fill and are emptied.

The ordering itself is right. What can be saved:

1. **No probes for one child, or for a run of fixed children.** With one
   child there is nothing to order. A child whose `flexibility(along:)` is
   `.fixed` takes the same length whatever it is offered, so its stretch is
   zero and it sorts first without being probed.
2. **Keep the probes across proposals.** How far a child stretches along
   the axis depends on what is proposed across it, not along it. Keep
   `(crossProposal, min, max)` per child in the stack's cache. When the
   stack is measured again at another width with the same height, which is
   what a window resize and a parent's own probes do, the order is already
   known.

## 3.3 Sizing and placing run the whole algorithm twice

**Today.** `StackContent.sizeThatFits` calls `layout`, and `place` calls
`layout` again under the same proposal. Each call allocates `sizes`,
`proposals`, `ranges` and `order`, runs the probes through the children's
caches, and sorts. A flattened `layoutChildren` array is built for each
call as well (3.8).

**Do instead.** Keep the last result on the node: the proposal it was made
under, the sizes, the child proposals and the total. `place` reuses it when
the proposal matches, which is the usual case.

This needs a place on the node for a content's own cache. With the generic
node of 1.2 it is `var cache: C.Cache`, the same idea the public `Layout`
protocol already has in its `Cache` type. Without phase 1, a stored
optional of one concrete stack cache type is enough to start.

The same result holds `isFixedRun`, which today asks every child's
flexibility on each call, and the stack's own flexibility, which today is
`node.layoutChildren.map { … }.max()` with an array made for it.

## 3.4 `HStack` and `HStackLayout` each get the cache

`HStack` and `HStackLayout` are two SwiftUI API types and stay two
implementations: `StackContent` for the stack views, `StackLayoutRun` for
the layout values. The same goes for `VStack` and `VStackLayout`.

3.2 and 3.3 apply to both, separately. Each keeps its own cache and its own
code:

- `StackContent` keeps its result on its node.
- `HStackLayout` and `VStackLayout` use the default empty `Cache` today and
  build a `StackLayoutRun` in `sizeThatFits` and again in `placeSubviews`. The
  `Layout` protocol's `Cache` is the place for it: the run's sizes, child
  proposals, gaps and total, made in `sizeThatFits`, reused in
  `placeSubviews`, and dropped in `updateCache` when the subviews change.

One thing seen while reading, noted only as a fact: with no `spacing:`
given, `StackContent` puts a fixed 8 points between children, while
`StackLayoutRun` asks each pair of neighbours for their spacing
preferences.

## 3.5 Capabilities found by casting

Covered in 1.2. In layout it shows up as:

- `LayoutSubview.spacing` doing `view.content as? LayoutSpacingSource`,
  twice per gap, in every `StackLayoutRun`;
- `invalidateMeasurementsUpwards` doing `content as? LayoutCacheOwner` for
  every ancestor on every scoped rebuild.

**Standalone version:** make both requirements of `NodeContent` with empty
defaults. The casts go away without the generic node.

## 3.6 A scoped rebuild empties every ancestor's cache

**Today.** After a scoped rebuild, `invalidateMeasurementsUpwards` clears
the measurements, the flexibilities and the preference cache of every node
from the replaced subtree's parent to the root. The next pass measures the
whole spine again.

Often the new subtree has the size the old one had: a label whose text
changed to another of the same width, a toggle that flipped, a color that
changed.

**Do instead.** Before clearing, measure the replacement under each
proposal the old node had cached and compare, along with its flexibility.
If every answer is the same, the ancestors' sizes cannot have changed and
their caches stay. The measurements are ones the next pass would take
anyway. Preferences need their own check, since they can change when the
size does not.

## 3.7 Modifiers measure again while placing

`FrameContent.place`, `ZStackContent.place`, `DecorationContent.place` and
`PositionContent.place` each call `child.sizeThatFits` to position the
child. The child's cache answers, so the cost is the lookup. With the
inline cache of 3.1 it is a few comparisons. Nothing further to do; listed
so nobody adds another cache for it.

## 3.8 `layoutChildren` builds an array on every call

**Today.** When a node has a transparent child (a `Group`, a `ForEach`, an
`if`) or a leaving child, `layoutChildren` builds a new flattened array.
It is called from `sizeThatFits`, `place` and `flexibility`, and in a loop
from `contentTransform` and `wrappedContentAccepts` in hit testing, where
only the count is wanted.

**Do instead.** Keep the flattened array on the node, and drop it when
`children` changes or a removal starts or ends. For the hit-testing loops,
a helper that finds "the only layout child, if there is exactly one"
without building anything.

## 3.9 Transform math (standalone)

[Transform.swift](../../Sources/NucleantUI/Layout/Transform.swift) and
[PaintBounds.swift](../../Sources/NucleantUI/Render/PaintBounds.swift).

- **`Rect.applying(_:)`** builds an array of four corners, then two more
  arrays with `map`, then takes `min()` and `max()` of each twice. It runs
  per command for `paintBounds` whenever a transform is set. Four points
  need no arrays: transform the corners into locals and take the lane-wise
  minimum and maximum with the helpers `Geometry.swift` already has. For a
  transform with no rotation, two corners are enough.
- **`Transform.around(_:_:)`** multiplies three matrices. The closed form
  keeps the four scale and rotation terms and sets the translation to
  `anchor - M * anchor`: four multiplications in place of twenty-four.
- **`isIdentity`** compares six doubles, and it is asked for every node
  placed and every node hit tested. Most transforms in a tree are the
  identity or a pure translation (`.offset`, a scroll position). A stored
  kind (identity, translation, general) answers `isIdentity` with one byte
  and gives translation its own short path: concatenating adds, inverting
  negates, applying to a rect adds to its origin.

## Order

1. 3.1 and 3.9: local, certain.
2. 3.5 standalone version.
3. 3.3, then 3.2 on top of the same cache, for `StackContent`.
4. 3.4: the same two for `HStackLayout` and `VStackLayout`, in their own
   `Cache`.
5. 3.8.
6. 3.6.

## Checking

- The `measured` count and the pass time in `NUCLEANT_SWIFTUI_TRACE_PERF=1`
  while resizing a window of a deep example, and during a scoped rebuild.
- The layout tests must give the same frames as before. 3.2 and 3.3 change
  no result, only how often it is computed.
