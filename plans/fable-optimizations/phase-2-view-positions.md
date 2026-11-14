# Phase 2: a position object instead of `[Int]` paths

## 2.1 What is keyed by a path today

A view's identity is its structural path: one `Int` per level, a `ForEach`
row by the hash of its id. The path is an `[Int]` value, and it is the key
of these tables:

| Subsystem | Tables keyed by `[Int]`, or by a struct holding one |
|---|---|
| State ([StateStore.swift](../../Sources/NucleantUI/State/StateStore.swift)) | `StateStore.slots` (`StateKey`), `StateStorage.readers`, `DependencyTracker.stack` and `.reads`, `Invalidator.dirtyPaths` |
| Effects ([BuildContext.swift](../../Sources/NucleantUI/Layout/BuildContext.swift)) | `EffectQueue.appeared`, `.disappearing`, `.observed`, `.geometryValues`, `.geometryTransitions` (all `StateKey`) |
| Animation ([AnimationStore.swift](../../Sources/NucleantUI/Animation/AnimationStore.swift)) | `values`, `observed`, `animatableData`, `animating`, `transitionSlots`, `finishedExits`, `timelines` |
| Preferences | `PreferenceObservers.observations` |
| Render nodes | `RenderNodeManager.nodes` and `.images`, `ThorCanvasNodes.nodes`, `TextureNodeManager.entries`, `RenderTextureManager.placements` (all `RenderNodeKey`, which holds a path) |
| Shaders | `ShaderSlotRegistry.slots`, `.changedInputs` |
| Navigation | `toolbars`, `backButtonHidden` |
| Nodes | `ViewNode.ownerPath`, `FocusTarget.path`, the gesture attachments' paths |

## 2.2 What that costs

**An array per node built.** `BuildContext.child(_:_:)` copies the context
and appends to `path`. The parent's copy is still alive, so the append
copies the array. Building N nodes at depth d allocates N arrays and copies
about N × d integers.

**Hashing an array on every use.** A path's hash covers every element.
Building one view hashes its path at least for `DependencyTracker.reads`
(`hasReads`, then `takeReads`, whether or not it read anything), once per
`StateKey` it binds, and once per animated value it asks for.

**Walks from the root.** `RebuildRecords.candidate(at:)` descends the trie
along the path for every view built, and `record(_:at:)` descends again
from the root to file the entry. The builder is walking the same tree in
the same order; it could hold a cursor and take one step per child.

**Cleanup in every subsystem.** Each table needs its own `forget(paths:)`,
called from the right places, and a missed one leaves stale entries. The
render node managers do it a different way, by what was claimed during the
pass.

## 2.3 Forgetting is a scan (standalone)

`EffectQueue.forget(paths:)` filters `appeared`, `observed`,
`geometryValues` and `geometryTransitions` whole, and loops over all of
`disappearing`, on every call. `buildNode` calls it with a set of one path
for each view whose identity changed at its position. Replacing a screen
of M views in a tree with K recorded effects costs M × K.

**Fix now**, without waiting for the rest of this phase: key those five
tables by path first, then by property index (`[[Int]: [Int: …]]`), so
forgetting a path is one removal per table. With the position object below,
the tables disappear.

## 2.4 The position is an object

The trie node at each path already exists, one per view position. Make
that object the identity, and let it hold what the tables above hold.

```swift
final class ViewPosition {
    unowned let parent: ViewPosition?
    let key: Int               // the slot in the parent
    let depth: Int
    // children, by key, as PathTrie.Node keeps them today

    // One build of the view standing here. Replaced by every rebuild.
    var record: Entry?
    var session: UInt64        // the rebuild that last built or kept it

    // The view standing here, for as long as it is the same view.
    // Cleared when another identity takes the position, or the view leaves.
    var identity: ViewIdentity
    // state slots, effects, animated values, … (2.6)
}
```

There are two lifetimes at one place in the tree, and the position keeps
them apart:

- **one build** of the view: the recorded view value, its node, the
  environment it was built under, what it read. Every rebuild replaces it;
- **the view standing there**: its state, its effects, its animated values.
  A rebuild of the same view keeps these. Another view taking the position,
  or the view leaving, clears them. `buildNode` already makes exactly this
  distinction with `replaced.identity != identity`.

`BuildContext` carries `position: ViewPosition` in place of `path: [Int]`.
`child(i)` is one lookup among the parent's children, which the builder
needs anyway to find the candidate. No array is made, and nothing is found
by walking from the root.

## 2.5 One trie, and a number per rebuild

Today a rebuild moves the subtree being rebuilt out of `live` into
`previous`, and moves each kept subtree back. With positions holding state,
the positions must stay where they are. A number does the job of the two
tries.

Every rebuild takes a new session number: a full one, a scoped one, a
`GeometryReader`'s during placement, an offscreen render's.

- **Candidate.** The builder steps to a child position. If it holds a
  record from an older session, that record is the candidate.
- **Kept.** The position's `session` is set to the current one. Nothing
  below it is touched. This replaces moving the subtree between tries, and
  costs the same whatever the subtree's size.
- **Rebuilt.** The record is replaced and `session` is set. If the identity
  is the one that stood there, what belongs to the view stays. Otherwise it
  is released, as today.
- **Left.** Once a rebuilt position's children are built, any child whose
  `session` is not the current one was neither rebuilt nor kept: it has left
  the tree. It is cut out and everything it and its subtree held is
  released, from one place. This finds what `leftoverChildren` and
  `endRebuild` find today, for one pass over the children of each rebuilt
  position.

Only the children of a rebuilt position are checked. A position deep inside
a kept subtree carries an older number, and that is harmless: nothing looks
at it until a rebuild reaches its parent.

**Dirty marks** work the same way with the frame's number. A state write
marks its position. At the start of a pass each dirty position walks up its
parents setting "something below is dirty in pass n", and stops at the first
one already marked. `isDirty(at:)` and `isDirty(under:)` each compare one
number. No trie of dirty paths is built per pass.

**A change arriving for a view that has left.** Today a dirty path with no
record makes `rebuildScoped` give up and the whole tree is rebuilt from the
root. A position knows it has left, so the change is dropped.

**To verify against the code while doing it**, since I did not read these
parts in full:

- a lazy container's rows outside its window, which are not built and so
  would count as left, as they do today;
- views leaving through a transition, whose nodes stay on screen after
  their records are gone (`TransitionSlots.swift`);
- the offscreen render's own root (`OffscreenRender.rootIndex`).

## 2.6 What a position can cache

Each row is something found by hashing a path today, or worked out again on
every build, that the position can simply hold.

| What | Today | On the position | Dropped when |
|---|---|---|---|
| The view's state slots | `StateStore.slots[StateKey]`, one hash of path, type and call site per `@State` per build | an array by property index | another identity, or the view leaves |
| `onAppear` mark, each `onChange`'s last value, the `onDisappear` action, `onGeometryChange` values | five dictionaries in `EffectQueue` | fields | same |
| Animated values of built-in modifiers | `values[path][slot]`, two hashes per modifier per build | a short array by slot | same |
| An `Animatable` view's state, its "still moving" mark, a timeline's next date | `animatableData`, `animating`, `timelines` | fields | same |
| Transition slots of a container | `transitionSlots[path]` | a field | same |
| The boundary's image, a shader slot, a canvas node, a texture entry | a dictionary keyed by `RenderNodeKey` in each manager, hashed per node per pass | a reference each | same; the manager is told, to retire the GPU object |
| The readers of a state slot | `readers[[Int]]` on the storage | the storage lists positions | the reader is rebuilt or leaves |
| A `ForEach`'s rows | the row's slot is the hash of its id (2.7) | a table from id to row position | the row leaves |
| The environment a modifier produced | written again on every build of the modifier, with a new stamp | the incoming environment's version, the value written, and the environment that came out | the incoming version differs, or the value is not equivalent |
| The path, for trace output | always carried | computed from the parents when a trace line is printed | never stored |

**About the environment row.** `EnvironmentValues.agrees(with:on:)` answers
at once when the two versions are equal. But a modifier that is rebuilt
writes its value again and gets a new stamp, even when the value is the one
it wrote last time. Every kept view below then compares each key it read,
by value. If the modifier's position remembers what came in and what it
wrote, and both are unchanged, it hands down the very environment it handed
down last time. Its version is the same, and every kept view below answers
with one comparison of two numbers.

## 2.7 `ForEach` rows

Three things in [ForEach.swift](../../Sources/NucleantUI/Views/ForEach.swift).

**A row's slot is the hash of its id.** `BuildContext.childSlot(for:)` uses
`id.hashValue` as the path component. Two different ids with the same hash
would share a position: one state, one record. With 64-bit hashes this is
very unlikely, and nothing detects it if it happens. A table from id to row
position on the `ForEach`'s position is keyed by the id itself.

**A change read in one row closure re-runs every row closure.** Each row
closure runs inside `trackingObservation(at: path)`, where `path` is the
`ForEach`'s own path. So a change to something one row's closure read
dirties the `ForEach`, and its rebuild runs `build(element)` for every
element and compares every row. What a row view reads inside its own `body`
is already scoped to that row. A
row position that keeps its element can be the scope for its own closure:
the change dirties that row, and the rebuild runs `build(element)` once.

**A `ForEach` is never equivalent.** `ForEach._isEquivalent` answers false,
so a parent re-running runs every row closure too. The data can be compared
like any other input, and the row closure by its captures, the way `@View`
already compares stored closures. A `ForEach` over the same data with
equivalent captures is then kept without running a single row closure.

A lazy container builds only the rows in its window, so these cost less
there. A plain `VStack` of a `ForEach` pays for every row.

## 2.8 Steps

1. 2.3, the forget fix.
2. 6.7, state reads kept on the tracker's stack frame. It removes one
   path-keyed table without touching identity.
3. `ViewPosition` in place of `PathTrie<Entry>.Node`, with the session
   number in place of the two tries (2.5). `BuildContext` gets `position`
   next to `path`, and the builder keeps a cursor. `path` stays for
   everything that still reads it. All tests pass before going on.
4. Move what is keyed by path onto the position, one subsystem at a time,
   in the order of the table in 2.6: state, effects, animation,
   transitions, render nodes, readers.
5. 2.7: the `ForEach` table, then the per-row scope, then equivalence.
6. The environment row of 2.6.
7. Remove `path` from `BuildContext`.

## Checking

- Allocations per view built, in Instruments.
- The build part of the pass time on a deep tree. The Atlas example's
  navigation push replaces a whole screen and exercises 2.3.
- A long non-lazy `ForEach` with one row's model changing (2.7): the count
  of nodes built in the perf trace should be one row's.
- Every test that checks state surviving a rebuild, `onAppear` and
  `onDisappear` firing once, animations continuing across a rebuild, and
  transitions in and out.
