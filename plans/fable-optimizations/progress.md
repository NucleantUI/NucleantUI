# Progress

What of [the review](README.md) is done, on the `optimizations` branch.
Each finding links its phase file; the hash is the commit that did it.

- [x] done
- [~] partly done — the note says what is left
- [ ] not started

Last updated after `96041c7`.

## Small fixes that are certain

- [x] Style unchanged at opacity 1, no gradient rebuilt (4.9) — `d350522`
- [x] `Rect.applying(_:)` without temporary arrays (3.9) — `d350522`
- [x] A node's two flexibilities as two stored values (3.1) — `d350522`
- [x] Focus and gesture targets found through `RebuildRecords` (7.2) — `d350522`
- [x] `EffectQueue.forget(paths:)` without filtering every table (2.3) — `d350522`
- [x] State reads kept on the tracker's stack frame (6.7) — `d350522`

## [Phase 1](phase-1-typed-modifiers-and-nodes.md): typed modifiers and nodes

- [x] **1.1** One type per modifier, compared by its values — `d1e038c`
- [x] **1.2** `ContentNode<C>` holds its content by type — `d24813b`
- [x] **1.3** Traits read once per node, unioned over the subtree — `d24813b`
- [ ] **1.4** Finding the builtin behind a view (`_makeNode`). Last in the
  plan's order: it changes the public `View` protocol.
- [x] **1.5** `ShapeContent<S>` holds the shape — `d6af0fd`
- [x] **1.6** `AnyView` as one storage object, equivalent as what it holds — `9914771`
- [x] **1.7** `OpaqueValue`/`OpaqueReference` as one `Box<T>` — `9914771`
- [x] **1.8** Comparing by a per-type witness, not through `Any` — `d1e038c`
- [x] **1.9** Built-in animated values as their own types — `f8eb992`.
  Colors and transitions keep their vector, as the commit says.
- [x] **1.10** Enums inside one content type — `e43a737`. Rotation and
  scale, background and overlay, are four kinds. `StackContent.axis` and
  `SpacerContent.axis` stay values: they feed the layout math, they do
  not pick what the node does.
- [x] **1.11** `ShapeStyle` is a protocol — `25eeafe`. Styles resolve
  where their view is built; examples, demo and tests moved over.

## [Phase 2](phase-2-view-positions.md): a position object instead of `[Int]` paths

- [x] **2.3** Forgetting without a scan — `d350522`
- [x] **2.4 / 2.5** The position object and one trie — `795a477` (step 3 of
  2.8). The rebuild records sit on `ViewPosition`s that stay in place;
  every rebuild takes a number. A kept subtree is one number set, and the
  views that left are found from the children of the positions rebuilt.
  What else the position holds is 2.6. The dirty marks stay a trie of
  paths: a write names its readers by the paths of their positions while
  they stand, and a build steps through the trie by slot, with no path.
- [x] **2.6** What a position caches — step 4 of 2.8, by the table's rows
  (the `ForEach` rows and the environment are steps 5 and 6):
  - [x] state slots — `3466a17`. By property index on the view's
    position; `StateStore` and the per-entry state keys are gone.
  - [x] effects — `37de011`. Fields of the modifier's position; the
    `onDisappear` actions of what leaves are collected as it is cut.
    `StateKey` is gone. Preference observers stay keyed by path.
  - [x] animated values — `c2e9d41`. A modifier's values by slot, an
    `Animatable`'s data, `.animation(_:value:)`'s last value and a
    timeline's next date are fields of the position; the rebuilds and
    timelines to come are lists of positions that pass by one that left.
  - [x] transition slots — `3085e1c`. On the container's position; a
    container that leaves hands back the exits it was playing, to end.
  - [x] render nodes — `268d4a1`, `7934fa3`. Every manager files a
    view's nodes — boundary images, canvases, texture, `ThorCanvas`,
    render-texture and shader slots — under a `RenderSlot` its position
    holds, hashed as an object, not under its path. Not "a reference
    each": the managers pool their GPU objects and hand them on, so a
    position holding one would need a check on every reuse that nobody
    still holds it. The managers' pools and retiring stay as they were.
  - [x] readers — `52b150c`. A state lists its readers by
    `PositionHandle`, which does not keep the position: a state can
    outlive its view. A view that leaves takes itself off as it is cut.
- [x] **2.7** `ForEach` rows
  - [x] a row's slot is the hash of its id — `10a442a`. A table by id on
    the `ForEach`'s position (`RowSlots`); a new id takes a slot no row
    there has had.
  - [x] a change read in one row closure re-runs every row closure —
    `46e2714`. Each row is a `ForEachRow` in its slot, the closure run in
    its scope; a row with an equivalent element and closure is kept
    without running it, also when the data around it changed.
  - [x] a `ForEach` compared like any other input — `5ce17e3`
- Steps of 2.8: all done.
  - 6 — `a266d81`: a modifier's last environment write on its position;
    the same write over the same environment hands down the same version.
  - 7 — `3c7a6a9` observation scopes, `4dd6041` owners (a node's maker, a
    state's view), `d3066e8` input targets, `fc626e4` `BuildContext`: all
    by `PositionHandle` or position. A build carries its position, not a
    path; `path` is worked out from the positions for trace lines and for
    what is filed in tree order (toolbars, preference observers). The dirty marks are
  still a trie of paths (`Invalidator`), made from the readers' paths.

## [Phase 3](phase-3-layout.md): layout caches and stack math

- [x] **3.1** A node's caches inline, not dictionaries — `d350522`
- [x] **3.2** A stack's children's stretch measured once — `d27ea61`
- [x] **3.3** A stack's last run kept for placing — `d27ea61`
- [x] **3.4** The same for `HStackLayout`/`VStackLayout`, separately — `d27ea61`
- [x] **3.5** Capabilities found by casting — no commit of its own: since
  1.3 both casts run only on nodes whose traits say they have the
  capability.
- [x] **3.6** A scoped rebuild keeps the ancestors' caches when the new
  subtree measures the same — `7326fb9`. Only for subtrees of kinds
  that place purely, and an old node whose cache dropped no answer.
- [x] **3.7** Nothing to do, by the plan.
- [x] **3.8** Flattened layout children kept on the node — `d27ea61`
- [x] **3.9** Transform math — `d350522`

## [Phase 4](phase-4-placement-and-display-list.md): placing and drawing only what changed

- [~] **4.1** Every pass places the whole tree
  - [x] step 1: a version per list in place of a deep comparison —
    `a0f05ce`. Per kept list rather than per leaf: a list that is a kept
    list, as it is or moved once (a boundary holding one kept subtree, in
    its image's space), compares by its number; any other list by its
    commands.
  - [x] step 2: skip a clean subtree — `ee269ed`. Kinds say whether they
    place purely (`NodeContent.placesPurely`, off by default); a clean,
    stable pure subtree appends what it kept. Clean means nothing asked for
    a frame and no state was read while it was placed. Checked in Bookmarks,
    Flashcards, MindMap and Reader by placing each appended subtree fresh
    too: about 70,000 appends, none different.
  - [x] step 3: a scrolled or moved subtree is kept too — `96041c7`. Not
    by frames relative to the boundary: a kept subtree placed at another
    origin (same size, proposal and context) is drawn moved, and its
    nodes' frames are moved with it, so hit testing stays as it is. Only
    while every clip in it is the context's, the context only moves, and
    no animation would start it moving. Bench scenarios for it:
    `bookmarks-scroll`, `reader-scroll` (`258f4e9`).
- [x] **4.2** Paths in their own space — `d6af0fd`
- [x] **4.3** The path kept on the node — `d6af0fd`
- [x] **4.4** One draw state shared by the five commands — `5e8fe6e`. The
  list keeps a `DrawState` per run of commands; each command has an index
  into them. The payloads stay inline in the command enum, not in side
  arrays.
- [x] **4.5** A path's elements as flat arrays — `b42bfcf`. `elements`
  and `Path.Element` stay as public API, made from the storage on each ask.
- [x] **4.6** `DrawContext` split into plain data and one shared reference —
  `9fafb43`. Turned clips, the shader canvas input, the animation and the
  coordinate spaces sit behind one object; the rest is plain data.
- [x] **4.7** Paint bounds worked out once — `1280e85` (a shape's path box,
  kept on the node), `5e8fe6e` (each command's bounds under its state, kept
  by the list when the command is appended).
- [x] **4.8** Text drawn from its lines — `d9ceb03`
- [x] **4.9** No gradient rebuilt at full opacity — `d350522`

## [Phase 5](phase-5-skia-drawing-and-text.md): Skia draw calls and text

- [x] **5.1** State set once per run of commands — `d9ceb03`
- [x] **5.2** A rect, rounded rect or ellipse drawn in one call — `d6af0fd`
- [x] **5.3** Gradient shaders and dash effects kept — `d9ceb03`
- [x] **5.4** A text blob per laid-out line — `cfc7fea`, after `d38f238`
  moved measuring to Skia (`SkiaFonts`, shared with the renderer). The
  blobs are kept by the renderer, by line, face and spacing, not with the
  layout entry: `TextDraw` is a value compared by its fields.
- [x] **5.5** Letter spacing — `cfc7fea`: a spaced line is the same blob,
  built once.
- [ ] **5.6** A font resolved to a small integer once.
- [ ] **5.7** The raster surface initializer. Not a performance item; goes
  when the pixel tests move to a software Vulkan driver.

## [Phase 6](phase-6-state-environment-bindings.md): environment, state writes, bindings

- [x] **6.1** Environment values as a chain of typed writes — `d46dd11`
- [x] **6.2** Environment reads as bits — `1bea9aa`
- [x] **6.3** Built-in modifiers write their own key — `d1e038c`
- [~] **6.4** Property wrappers without a holder — `7dd3cdc`.
  `@Environment`, `@Namespace` and `@FocusState` are bound in place and
  allocate nothing. `@State` keeps its holder: see the open decisions.
- [x] **6.5** A binding writes the part it points at — `e62b0b7`
- [x] **6.6** A write looks only at the readers it can reach — `e62b0b7`
- [x] **6.7** Reads on the tracker's stack frame — `d350522`

## [Phase 7](phase-7-input.md): hit testing and focus lookups

- [x] **7.1** Every hit test walks every node
  - [x] step 1: skip subtrees without the wanted trait — `d24813b`
  - [x] step 2: one walk per pointer down — `226d865`
  - [x] step 3: skip a subtree placed away from the point — `28806dd`. Not by
    paint bounds — a view that paints nothing can still be hit — but by
    where its subtree can be hit: each node keeps the box of its frames
    under the transforms they are drawn with (`hitExtent`), noted as it is
    placed and moved with a moved subtree; both walks pass over a subtree
    whose box does not hold the point.
- [x] **7.2** Finding a node by path — `d350522`; the focus-binding walk
  is skipped through the trait bit since `d24813b`.
- [x] **7.3** Covered by 3.8: the single-child loops read the cached
  layout children.
- [x] **7.4** A move undone by subtraction — `5ce17e3`. A general
  transform's inverse is still worked out when needed, not kept.
- [x] **7.5** Preference observers kept in order — `297141f`

## Not in the plan, done on the way

- `43a7f32` — closure equivalence read a context whose capture layout is
  only known at run time (one holding a Foundation `Date`) from its header.
  Bookmarks crashed comparing the inspector's buttons.
- `116a331` — `DrawContext` no longer carries the color scheme: since 1.11
  nothing read it there.

## Open decisions

- **`@State`'s holder (6.4).** A write in an initializer to a state that
  has an initial value (`self.value = start`) is the state's first value;
  it goes through a nonmutating setter before the view is bound, so it
  needs a shared reference. Removing the holder means dropping that
  feature, as SwiftUI ignores such writes.
- **`.primary`, `.secondary`, `.tertiary` (1.11).** Fixed light/dark grays,
  as before. In SwiftUI they derive from the foreground style in effect;
  switching changes how text looks in several examples.

## Measuring

Every before/after run of `Scripts/bench_animations.py` that a step was
judged by, kept in [measurements.json](measurements.json) with each
launch's numbers. Run both commits, then `record <before> <after> --what
"…"`; the tables below are written from the record.

<!-- measurements:summary -->
CPU per pass, mean of the launches (debug builds); in **bold** where the
launches before and after don't overlap. Written by
`Scripts/bench_animations.py tables` from [measurements.json](measurements.json).

| Measured | Before → after | Date | Load | `bookmarks-layout` | `flashcards-card` |
|---|---|---|---|---|---|
| Before phase 2: phases 1 (but 1.4) and 3, 2.3, 2.7's `ForEach` comparison, 4.1 steps 1–2, 4.2–4.9, 5.1–5.3, 6 (6.4 in part), 7.1 steps 1–2, 7.2–7.5 | `4adf040` → `f6c6802` | 2026-11-14 | not recorded | 73.5 → 33 ms (**−55%**) | 3.33 → 2.95 ms (**−11%**) |
| 2.8 steps 5 and 6: `ForEach` rows by id, a scope per row, a modifier's environment write kept | `10a442a` → `a266d81` | 2026-11-14 | about 3–7 | 34.5 → 34.5 ms (+0%) | 2.91 → 2.72 ms (**−7%**) |
| 2.8 step 7: no paths in the build | `a266d81` → `fc626e4` | 2026-11-14 | about 12 | 34.8 → 32.7 ms (−6%) | 2.9 → 2.88 ms (**−1%**) |
<!-- /measurements:summary -->

<details>
<summary>Every metric, per measurement</summary>

<!-- measurements:details -->
#### Before phase 2: phases 1 (but 1.4) and 3, 2.3, 2.7's `ForEach` comparison, 4.1 steps 1–2, 4.2–4.9, 5.1–5.3, 6 (6.4 in part), 7.1 steps 1–2, 7.2–7.5

`4adf040` → `f6c6802`, 2026-11-14, debug builds, load not recorded; `bookmarks-layout` 3/3 launches of 5 rounds, `flashcards-card` 3/3 launches of 5 rounds.

| | `bookmarks-layout` | `flashcards-card` |
|---|---|---|
| CPU per pass | 73.5 → 33 ms (**−55%**) | 3.33 → 2.95 ms (**−11%**) |
| building per pass | 47 → 12.8 ms (**−73%**) | 0.314 → 0.238 ms (**−24%**) |
| median pass | 67.5 → 27.9 ms (**−59%**) | 1.6 → 1.1 ms (**−31%**) |
| 95th percentile pass | 76.5 → 34.6 ms (**−55%**) | 2.2 → 1.53 ms (**−30%**) |
| slowest pass | 82.3 → 41.3 ms (**−50%**) | 6.63 → 4.3 ms (**−35%**) |
| passes for the interaction | 69.3 → 138 (**+100%**) | 791 → 790 (−0%) |
| CPU for the interaction | 5.09 → 4.57 s (−10%) | 2.63 → 2.33 s (**−11%**) |
| nodes built, all passes | 28,917 → 43,261 (**+50%**) | 1,964 → 1,920 (**−2%**) |
| sizes measured, all passes | 57,913 → 106,078 (**+83%**) | 22,216 → 20,704 (**−7%**) |
| texts measured, all passes | 7,516 → 15,128 (**+101%**) | 2,613 → 2,621 (+0%) |

#### 2.8 steps 5 and 6: `ForEach` rows by id, a scope per row, a modifier's environment write kept

`10a442a` → `a266d81`, 2026-11-14, debug builds, load about 3–7; `bookmarks-layout` 3/3 launches of 5 rounds, `flashcards-card` 3/3 launches of 5 rounds.

| | `bookmarks-layout` | `flashcards-card` |
|---|---|---|
| CPU per pass | 34.5 → 34.5 ms (+0%) | 2.91 → 2.72 ms (**−7%**) |
| building per pass | 12.7 → 13.4 ms (+6%) | 0.221 → 0.209 ms (**−5%**) |
| median pass | 28.8 → 30 ms (+4%) | 1.1 → 1.07 ms (−3%) |
| 95th percentile pass | 41.8 → 36.8 ms (−12%) | 1.5 → 1.5 ms (+0%) |
| slowest pass | 71.9 → 44.7 ms (−38%) | 4.53 → 4.1 ms (−10%) |
| passes for the interaction | 134 → 133 (−1%) | 793 → 791 (−0%) |
| CPU for the interaction | 4.61 → 4.59 s (−0%) | 2.3 → 2.15 s (**−7%**) |
| nodes built, all passes | 42,089 → 41,867 (−1%) | 1,927 → 1,811 (**−6%**) |
| sizes measured, all passes | 103,143 → 102,190 (−1%) | 20,738 → 20,685 (−0%) |
| texts measured, all passes | 14,845 → 14,660 (−1%) | 2,626 → 2,621 (−0%) |

#### 2.8 step 7: no paths in the build

`a266d81` → `fc626e4`, 2026-11-14, debug builds, load about 12; `bookmarks-layout` 3/3 launches of 5 rounds, `flashcards-card` 3/3 launches of 5 rounds.

| | `bookmarks-layout` | `flashcards-card` |
|---|---|---|
| CPU per pass | 34.8 → 32.7 ms (−6%) | 2.9 → 2.88 ms (**−1%**) |
| building per pass | 13.4 → 12 ms (**−10%**) | 0.221 → 0.21 ms (**−5%**) |
| median pass | 29.6 → 28 ms (−5%) | 1.07 → 1.07 ms (+0%) |
| 95th percentile pass | 39.3 → 33.5 ms (−15%) | 1.5 → 1.5 ms (+0%) |
| slowest pass | 46.3 → 37.2 ms (−20%) | 4.03 → 3.77 ms (−7%) |
| passes for the interaction | 134 → 141 (+6%) | 790 → 790 (−0%) |
| CPU for the interaction | 4.64 → 4.61 s (−1%) | 2.29 → 2.28 s (−1%) |
| nodes built, all passes | 42,018 → 44,139 (+5%) | 1,822 → 1,816 (−0%) |
| sizes measured, all passes | 102,549 → 108,516 (+6%) | 20,682 → 20,692 (+0%) |
| texts measured, all passes | 14,694 → 15,902 (+8%) | 2,616 → 2,616 (+0%) |
<!-- /measurements:details -->

</details>

Not in the record: `0f10917` counted Bookmarks' Cards/List rebuild from
samples, 1171 before and 881 after (debug build).

## Outside this repo

These use the style API and need the same changes as the examples when
they move to this NucleantUI (1.11): NucleantCEF, NucleantLayouts,
NucleantMonaco, NucleantTransitions, NucleantUI_PyShader, PyShader.
