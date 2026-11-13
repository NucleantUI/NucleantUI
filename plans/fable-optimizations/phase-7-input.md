# Phase 7: hit testing and focus lookups

## 7.1 Every hit test walks every node

**Today.** `ViewNode.hitTest(_:select:)` in
[HitTesting.swift](../../Sources/NucleantUI/Layout/HitTesting.swift) visits
every node in the tree, front to back, until one answers. Only a clipping
node or a parked subtree stops the descent. A child may draw outside its
parent's frame, so frames cannot be used to skip.

At each node it asks the content, through the existential, `isParked`,
`allowsHitTesting`, `clipsChildren`, `hitShape` and `hitTestOrder`, and
then calls `select`.

Each event runs several of these walks
([ViewHost.swift](../../Sources/NucleantUI/App/ViewHost.swift)):

| Event | Walks |
|---|---|
| A mouse move with no button down | 2: `updateHover`, `updateTextureHover` |
| A pointer down | up to 5: `updateFocus`, the scroll target, the drag source, the context menu source, `pressChain` |
| A scroll wheel event | 1 |

A mouse moving over a window of 2,000 nodes with no `.onHover` anywhere
visits 4,000 nodes per move and finds nothing.

**Do instead.**

1. **Skip subtrees that cannot answer.** With the trait set of 1.3, each
   node holds the union of the traits in its subtree. It is computed when
   the node is made, since the children already exist then, and updated up
   the parent chain in `replaceChild`, stopping where the union does not
   change. A walk looking for a hover target returns at once from any
   subtree without the hover bit. In an app with no `.onHover`, the walk
   ends at the root.
2. **One walk per event.** A pointer down needs the frontmost press
   target, drag source, menu source, focus target and scroll target at one
   point. One descent can collect all of them.
3. **Later, with phase 4:** once a boundary knows the bounds of what it
   paints, a point outside those bounds skips the boundary.

## 7.2 Finding a node by path walks the tree (standalone)

**Today.** `focusTarget(at:)` in
[KeyFocus.swift](../../Sources/NucleantUI/App/KeyFocus.swift), and
`focusNode(at:)` and `gestureAttachment(at:)`, recurse through every node
comparing `target.path == path`.

- `applyFocusRequests` runs after every pass that built anything. While a
  text field has the keys, that is a whole-tree walk after every
  keystroke.
- `focusBindings(into:)` collects every `.focused` mark by walking the
  whole tree, also after every pass that built, whether or not the app
  uses `@FocusState`.

**Do instead.**

- `RebuildRecords.node(for:)` finds the node at a path in as many steps as
  the path is long. Start from that node and look only below it.
- Focus bindings register when they are built, in a list the host keeps,
  the way `PreferenceObservers` does it. Or, with 7.1, the walk is skipped
  when the root's subtree has no focus-binding bit.

## 7.3 Following a chain of single children builds arrays

**Today.** `contentTransform` and `wrappedContentAccepts` loop down a run
of single-child nodes by calling `layoutChildren` and checking that its
count is 1. When a node has a transparent or leaving child, each call
builds a flattened array to count it. They run for every hit found, and
for every node in a press chain.

**Do instead.** The helper from 3.8 that returns the only layout child, if
there is exactly one, without building an array.

## 7.4 A transform is inverted per node

**Today.** `mapIntoLocalSpace` calls `transform.inverted()` for each
clipping or shaped node under a transform, for each walk.

**Do instead.** With the transform kind of 3.9, a translation, which is
the common case under `.offset` and inside scroll views, is undone by a
subtraction. A general transform's inverse can be kept on the node when it
is placed.

## 7.5 Preference observers are sorted every pass

`PreferenceObservers.changes()` sorts all observations by path after every
pass that built. Small. Keeping them in order when they are added avoids
it.

## Order

1. 7.2, which needs nothing else.
2. 7.3 with 3.8.
3. 7.1 step 1 once the trait set of 1.3 exists, then step 2.
4. 7.4 with 3.9.

## Checking

- Time Profiler while moving the mouse over a large example without
  pressing: the time under `hitTest` should drop to near nothing when the
  app has no hover handlers.
- Typing in a text field on a large screen: the time under
  `applyFocusRequests`.
- The input tests: taps, drags, hover, focus and context menus must reach
  the same views as before.
